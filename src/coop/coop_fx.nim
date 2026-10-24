## Co-op presentation events: the host's effects, shown on the clients.
##
## A client never runs the simulation, so the things the simulation only
## *shows* -- sounds, particle bursts, damage numbers and the other floating
## text, lightning, blast rings, screen shake -- would never happen on its
## screen (none of it is run state the snapshots carry). Instead, while the
## host's simulation runs (`coopFxRecording`), each effect helper logs one
## event with what it was asked for; coop_session sends the log with the
## snapshots and the client replays every event through the same helper
## (coop_present). One event per burst, never per particle: the client rolls
## its own particles.
##
## Each event carries the player whose context raised it (`coopFxSlot`, kept by
## withPlayer; -1 for the world), so a teammate's sounds play quieter and only
## the player concerned feels a screen shake, on the host as on the clients.
##
## The lowest co-op module (raylib only), so particle_pool, sound and d_systems
## can log: it also holds `localSlot`, which coop_context re-exports.

import raylib

type
  CoopFxKind* = enum
    fxSound          ## playSound: `a` the sound, `x` volume, `y` pitch
    fxShake          ## addShake: `a` the intensity, `color` the tint
    fxExplosion      ## spawnExplosionPooled: `a` the count
    fxTrail          ## spawnTrailParticlePooled: `a` the count
    fxSparkRing      ## spawnShockwavePooled: `z` the radius
    fxExplosiveRing  ## spawnExplosiveRingPooled: `z` the radius, `a` the rings
    fxSpiral         ## spawnSpiralExplosionPooled: `z` the radius, `a` the arms
    fxNova           ## spawnNovaExplosionPooled: `z` the radius, `color`, `color2`
    fxDeathBurst     ## spawnEnemyDeathBurst: `z` the enemy's radius, `a` 1 for a boss
    fxShotParticles  ## spawnShootingParticles: (`z`, `w`) the direction, `a` the skin
    fxPlayerDeath    ## spawnPlayerDeathExplosion
    fxFizzle         ## a boss-death sweep's freed hazard (blastFreeFizzle)
    fxDamage         ## showDamage: `z` the amount, `a` 1 from a player + 2 critical,
                     ## `b` the damage type
    fxCurrency       ## a currency indicator: `a` the amount, `b` its kind
    fxPerk           ## showPerk: `text`, `color`
    fxLightning      ## spawnLightningBolt: (`x`, `y`) to (`z`, `w`)
    fxBlastRing      ## spawnShockwaveRing: `z` the radius
    fxPathBlast      ## spawnPathShockwave: `points`, `z` the width
    fxPlayerSignal   ## a hit's one-frame signal (player.signalDamageEvent): `a`
                     ## the DamageEvent, `b` the player's slot
    fxInstallCard    ## a power-up installed: `a` its type, `b` level, `c` rarity,
                     ## `d` the player's slot (whose screen shows the card)
    fxDamage3D       ## a 3D world's floating number: (`x`, `y`, `z`), `w` the amount
    fxShake3D        ## a 3D world's camera shake (world3d.shake): `x` the seconds

  CoopFx* = object
    id*: uint32       ## the host's running count (a client shows each id once)
    kind*: CoopFxKind
    slot*: int8       ## the player whose context raised it; -1: the world
    a*, b*, c*, d*: int32
    x*, y*, z*, w*: float32
    color*, color2*: Color
    text*: string
    points*: seq[Vector2]

const
  TeammateSoundVolume* = 0.45'f32
    ## A sound raised in a teammate's context (their shot, their hit) plays at
    ## this share of its volume.
  MaxFxBatch* = 600
    ## Events one snapshot carries at most (the oldest go first).

var
  localSlot*: int32
    ## The slot this machine's keyboard/pad drives (co-op; 0 in single player).
  coopFxSlot*: int32 = -1
    ## The player whose context the simulation runs (withPlayer); -1 outside one.
  coopFxRecording*: bool
    ## Host: the run's simulation is running, so its effects are logged.
  coopFxLog*: seq[CoopFx]
    ## Host: the effects logged since the last snapshot went out.
  coopFxInbox*: seq[CoopFx]
    ## Client: the host's effects, waiting to be shown (coop_present).
  coopFxInboxSnaps*: int
    ## Client: snapshots whose effects wait in the inbox. Nothing shows them
    ## while a team modal is up, and effects that late are dropped, not shown.

proc logFx*(ev: CoopFx) =
  var e = ev
  e.slot = int8(clamp(coopFxSlot, -1, 127))
  if coopFxLog.len >= MaxFxBatch * 2:
    coopFxLog.delete(0)
  coopFxLog.add e

template recordFx*(ev: CoopFx) =
  ## The host's simulation shows an effect: log it for the clients. `ev` is
  ## only built while recording.
  if coopFxRecording: logFx(ev)

template unrecorded*(body: untyped) =
  ## Run `body` logging nothing: its effects ride on an event already logged.
  let fxWas = coopFxRecording
  coopFxRecording = false
  try:
    body
  finally:
    coopFxRecording = fxWas

proc teammateContext*(): bool {.inline.} =
  ## The simulation runs in another player's context than this machine's.
  coopFxSlot >= 0 and coopFxSlot != localSlot
