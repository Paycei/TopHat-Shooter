## Survival / Roguelite roster hazards: timing constants and the pure geometry
## shared by the three places that touch a hazard - its spawn (ui/mode_warnings
## and mode_enemies), its resolution (game/mode_mechanics) and its drawing
## (mode_visuals). Anything that moves over a warning's life is a pure function
## of the warning here, so the hit test and the render can never disagree.
##
## Leaf module: imports only math and types.

import math
import particle_types, types

const
  # --- Enemies -------------------------------------------------------------
  ForkBombSelfForkTime* = 12.0'f32   ## An ignored Fork Bomb forks a copy after this
  ForkBombChargeLead* = 3.0'f32      ## ...showing a visible charge-up for this long first
  ForkBombMaxCopies* = 1             ## generation cap: a copy never forks again
  ZombieReanimateTime* = 4.0'f32     ## A husk stands back up after this
  ZombieReapRadius* = 26.0'f32       ## Walk this close to a husk to reap it
  ZombieReviveHpFrac* = 0.5'f32
  DeadlockArmDelay* = 1.0'f32        ## A fresh pair's tether is harmless this long
  DeadlockMaxTether* = 380.0'f32     ## Beyond this the tether is overstretched (harmless)
  DeadlockTetherHalfWidth* = 5.0'f32
  DeadlockTetherInterval* = 0.5'f32  ## Seconds between tether hits
  DaemonAuraRadius* = 190.0'f32
  DaemonHaste* = 0.30'f32
  InterruptTriggerRange* = 260.0'f32
  InterruptMarkTime* = 0.75'f32      ## Stands still marking its spot
  InterruptDashSpeed* = 520.0'f32
  InterruptBlastRadius* = 72.0'f32
  InterruptDeathBlastRadius* = 48.0'f32  ## Smaller pop when shot before it lands
  InterruptBlastEnemyFrac* = 0.6'f32     ## Share of max HP the blast takes from the horde
  FragmentHopTime* = 0.3'f32
  FragmentRestTime* = 0.25'f32
  FragmentPounceRange* = 250.0'f32   ## Crouches to pounce once the player is this close
  FragmentTrackTime* = 0.35'f32      ## Crouched: its landing mark follows where the player is heading
  FragmentLockTime* = 0.2'f32        ## Mark locked: last beat to change course
  FragmentLeapTime* = 0.3'f32        ## Fixed flight time, so the slam always lands on the beat
  FragmentLeapRange* = 280.0'f32     ## Longest pounce (the mark is pulled in past this)
  FragmentSlamRadius* = 30.0'f32
  FragmentRecoverTime* = 0.6'f32     ## Grounded after the slam: shoot it now
  FragmentPounceCooldown* = 1.2'f32
  PortGuardShieldHalfArc* = 1.05'f32  ## Radians each side of the facing that block shots
  PortGuardTurnRate* = 1.4'f32
  SentryPostTimeout* = 3.5'f32
  MimicWakeRadius* = 125.0'f32
  MimicLungeTime* = 0.5'f32
  MimicLungeSpeed* = 330.0'f32
  RestorerSeekRange* = 420.0'f32
  RestorerChannelRange* = 150.0'f32
  RestorerChannelTime* = 1.5'f32
  RestorerCooldown* = 2.5'f32
  CorpseLifetime* = 8.0'f32
  PacketWindup* = 0.6'f32
  PacketBounces* = 3
  PacketMaxDash* = 2.2'f32
  PacketRest* = 1.4'f32
  DriverTriggerRange* = 380.0'f32
  DriverWindup* = 0.9'f32
  DriverMaxCharge* = 1.4'f32
  DriverStunTime* = 2.0'f32
  DriverRecover* = 1.2'f32
  DriverFrontArmor* = 0.35'f32       ## Damage taken from the front
  DriverStunVulnerability* = 2.0'f32 ## Damage taken while stunned
  CorruptorDropInterval* = 1.4'f32
  CorruptorMaxTiles* = 6
  CorruptTileArm* = 0.6'f32
  CorruptTileActive* = 6.0'f32
  CorruptTileHalf* = 18.0'f32
  CorruptTileInterval* = 0.5'f32

  # Boss-spawned ballistic units (fork seeds, payload orbs, marching ranks).
  BallisticMarcher* = -1             ## generation of a marcher: never stops, leaves off-screen

  # --- Survival bosses -------------------------------------------------------
  ForkTreeSeedRadius* = 9.0'f32
  MarchLaneTelegraph* = 1.3'f32
  MarchRankRows* = 2                 ## Two staggered rows: no gap to walk through, shoot one
  MarchRankRowGap* = 30.0'f32
  MarchRankStagger* = 1.1'f32        ## Seconds between successive ranks of one cast
  HeatNodeSpacing* = 24.0'f32
  HeatTrailArm* = 0.7'f32
  HeatTrailActive* = 3.5'f32
  HeatTrailInterval* = 0.5'f32       ## Player hit cadence in the trail
  HeatTrailEnemyDps* = 0.35'f32      ## Share of max HP per second the trail burns off the horde
  ThermalVentTelegraph* = 1.2'f32
  ThermalVentActive* = 0.25'f32
  ThermalVentCell* = 128.0'f32       ## Crowd density grid for picking vent spots
  SafeModeTelegraph* = 1.4'f32
  SafeModeStartRadius* = 230.0'f32
  SafeModeEndRadius* = 145.0'f32
  SafeModeInterval* = 0.5'f32
  SafeModePull* = 90.0'f32           ## px/s the horde is dragged toward the bubble
  PriorityBoostTime* = 3.0'f32

  # --- Roguelite guardians --------------------------------------------------
  SearchlightTelegraph* = 1.0'f32
  SearchlightHalfWidth* = 13.0'f32
  SearchlightLength* = 1400.0'f32
  SearchlightInterval* = 0.45'f32
  FileBombShredRadius* = 30.0'f32
  FileBombBlastRadius* = 66.0'f32
  FileBombShrapnel* = 6
  FileBombPurgeFlash* = 0.3'f32       ## Active window at the purge
  RestorePointHealCap* = 0.35'f32     ## A rollback restores at most this share of the phase pool
  AuditTelegraph* = 1.2'f32
  AuditMoveTolerance* = 12.0'f32
  AuditGrace* = 0.18'f32            ## Reaction time after the lock before a move/shot counts
  PacketCars* = 6
  PacketCarSpacing* = 26.0'f32
  PacketRadius* = 7.0'f32
  PacketLinkStagger* = 0.35'f32
  PacketHitInterval* = 0.6'f32       ## One train = one hit (its cars don't stack)
  PageFaultActive* = 0.2'f32
  PageFaultMaxWalls* = 9
  PageFaultRadiusMin* = 28.0'f32
  PageFaultRadiusMax* = 38.0'f32
  EchoSampleRate* = 30.0'f32
  EchoBufferSeconds* = 6.0'f32
  EchoShotInterval* = 0.3'f32
  EchoRadius* = 12.0'f32
  EchoFadeIn* = 0.4'f32
  LkgReveal* = 0.9'f32               ## Doors light up before the purge starts
  LkgActive* = 0.35'f32              ## Judgement flash at the end
  LkgDoorDepth* = 120.0'f32          ## How far the safe alcove reaches in from the edge
  LkgDoorWidth* = 150.0'f32
  LkgPurgeDelay* = 0.45'f32          ## Share of the run before the purge front leaves the centre

proc echoCapacity*(): int {.inline.} =
  int(EchoSampleRate * EchoBufferSeconds)

proc warningAge*(w: AttackWarning): float32 {.inline.} =
  ## Seconds since the warning was spawned.
  w.maxLifetime - w.lifetime

# ---------------------------------------------------------------------------
# Geometry

proc pointSegmentDistance*(p, a, b: Vector2f): float32 =
  let abx = b.x - a.x
  let aby = b.y - a.y
  let denom = abx * abx + aby * aby
  let t = if denom > 0.0001'f32:
            clamp(((p.x - a.x) * abx + (p.y - a.y) * aby) / denom, 0.0'f32, 1.0'f32)
          else: 0.0'f32
  let dx = p.x - (a.x + abx * t)
  let dy = p.y - (a.y + aby * t)
  sqrt(dx * dx + dy * dy)

proc portGuardBlocks*(enemy: Enemy, hitFrom: Vector2f): bool =
  ## True when a hit arriving from `hitFrom` lands on a Port Guard's shield
  ## (rotation = shield facing).
  if enemy.enemyType != etPortGuard or enemy.hp <= 0:
    return false
  let toSrc = hitFrom - enemy.pos
  if toSrc.length() < 0.001'f32:
    return false
  let a = arctan2(toSrc.y, toSrc.x)
  var diff = a - enemy.rotation
  while diff > PI: diff -= 2.0'f32 * PI
  while diff < -PI: diff += 2.0'f32 * PI
  abs(diff) < PortGuardShieldHalfArc

proc rayCircleHit(origin, dir: Vector2f, center: Vector2f, radius: float32): float32 =
  ## Distance along the (unit) ray to the circle, or -1 when it misses.
  let ox = origin.x - center.x
  let oy = origin.y - center.y
  let b = ox * dir.x + oy * dir.y
  let c = ox * ox + oy * oy - radius * radius
  if c <= 0: return 0.0'f32        # starts inside
  let disc = b * b - c
  if disc < 0: return -1.0'f32
  let t = -b - sqrt(disc)
  if t < 0: -1.0'f32 else: t

proc rayWallDistance*(origin, dir: Vector2f, maxLen: float32, walls: seq[Wall]): float32 =
  ## How far a (unit-direction) ray travels before a standing wall stops it.
  ## Slab walls are approximated by their inscribed circle along the face.
  result = maxLen
  for wall in walls:
    if wall.hp <= 0: continue
    let r = if wall.slabShape: wall.radius * 0.8'f32 else: wall.radius
    let t = rayCircleHit(origin, dir, wall.pos, r)
    if t >= 0 and t < result:
      result = t

# --- Searchlight (Gatekeeper) ----------------------------------------------
# laserAngles = beam base angles, bulletSpeed = angular speed (rad/s, signed),
# ricochetPath = per-beam clipped end points (refreshed every frame by the
# resolver, read by the renderer).

proc searchlightAngle*(w: AttackWarning, beam: int): float32 =
  let age = max(0.0'f32, warningAge(w) - SearchlightTelegraph)
  w.laserAngles[beam] + w.bulletSpeed * age

proc searchlightLive*(w: AttackWarning): bool {.inline.} =
  warningAge(w) >= SearchlightTelegraph and w.lifetime > 0

# --- Safe Mode (Omega, survival) --------------------------------------------
# pos = bubble start, targetPos = bubble end, lifetime spans telegraph + cast.

proc safeModeProgress*(w: AttackWarning): float32 =
  ## 0 at the end of the telegraph, 1 when the cast ends.
  let castLen = max(0.01'f32, w.maxLifetime - SafeModeTelegraph)
  clamp((warningAge(w) - SafeModeTelegraph) / castLen, 0.0'f32, 1.0'f32)

proc safeModeBubble*(w: AttackWarning): tuple[center: Vector2f, radius: float32] =
  let p = safeModeProgress(w)
  let s = p * p * (3.0'f32 - 2.0'f32 * p)   # smoothstep drift
  (newVector2f(w.pos.x + (w.targetPos.x - w.pos.x) * s,
               w.pos.y + (w.targetPos.y - w.pos.y) * s),
   SafeModeStartRadius + (SafeModeEndRadius - SafeModeStartRadius) * p)

proc safeModeFlooding*(w: AttackWarning): bool {.inline.} =
  warningAge(w) >= SafeModeTelegraph and w.lifetime > 0

# --- Last Known Good (Omega, roguelite) -------------------------------------
# bulletCount = index of the real door (0 top, 1 right, 2 bottom, 3 left),
# laserPattern = the four door labels joined by '|', pos = room centre,
# laserLength = distance from the centre to the farthest corner.

proc lkgDoorRect*(door: int, screenW, screenH: float32): tuple[x, y, w, h: float32] =
  ## The alcove in front of door `door` that shelters the player.
  let half = LkgDoorWidth / 2.0'f32
  case door
  of 0: (screenW / 2 - half, 0.0'f32, LkgDoorWidth, LkgDoorDepth)
  of 1: (screenW - LkgDoorDepth, screenH / 2 - half, LkgDoorDepth, LkgDoorWidth)
  of 2: (screenW / 2 - half, screenH - LkgDoorDepth, LkgDoorWidth, LkgDoorDepth)
  else: (0.0'f32, screenH / 2 - half, LkgDoorDepth, LkgDoorWidth)

proc lkgInDoor*(door: int, p: Vector2f, screenW, screenH: float32): bool =
  let r = lkgDoorRect(door, screenW, screenH)
  p.x >= r.x and p.x <= r.x + r.w and p.y >= r.y and p.y <= r.y + r.h

proc lkgPurgeRadius*(w: AttackWarning): float32 =
  ## The purge front, from 0 at the end of the reveal to the far corners by
  ## the judgement.
  let runLen = max(0.01'f32, w.maxLifetime - LkgReveal - LkgActive)
  let p = clamp((warningAge(w) - LkgReveal) / runLen, 0.0'f32, 1.0'f32)
  # The centre holds for a beat, so the way to the true door is open at first.
  let k = clamp((p - LkgPurgeDelay) / (1.0'f32 - LkgPurgeDelay), 0.0'f32, 1.0'f32)
  k * w.laserLength

# --- Packet Switching (Router) -----------------------------------------------
# pos = link start (an arena edge), targetPos = link end, bulletSpeed = train
# speed, laserDuration = telegraph before the train leaves. The train is a
# moving segment of PacketCars packets, a pure function of the warning's age,
# so it hits once per pass instead of once per car.

proc packetLinkLength*(w: AttackWarning): float32 {.inline.} =
  distance(w.pos, w.targetPos)

proc packetTrain*(w: AttackWarning): tuple[live: bool, tail, head: Vector2f] =
  ## The stretch of the link the train covers right now (clipped to the link).
  let run = warningAge(w) - w.laserDuration
  if run < 0: return (false, w.pos, w.pos)
  let len = packetLinkLength(w)
  let dir = (w.targetPos - w.pos).normalize()
  let headD = run * w.bulletSpeed
  let tailD = headD - (PacketCars - 1).float32 * PacketCarSpacing
  if tailD >= len: return (false, w.targetPos, w.targetPos)
  let h = min(headD, len)
  let tl = max(tailD, 0.0'f32)
  (true, w.pos + dir * tl, w.pos + dir * h)
