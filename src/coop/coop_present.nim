## Co-op client: the host's effects, shown on this machine (see coop_fx).
##
## Each event the host logged goes back through the helper that logged it, so
## a client's sounds, bursts, floating numbers and rings are the host's, rolled
## with this machine's own particles. A teammate's sounds play quieter and only
## this player's screen shakes for their own hits. Every number from the wire
## is checked or clamped first: an event can't name a sound that isn't one or
## ask for a million particles.

import raylib
import ../modding/mod_patch_core
import ../types, ../particle_pool, ../particle_skins, ../sound, ../d_systems
import ../game/[combat, bullets, death]
import ../game3d/game_3d
import coop_context

const
  MaxFxParticles = 400'i32   ## a burst's count at most
  MaxFxRadius = 4000'f32     ## a ring's radius at most

proc enumOk[E: enum](v: int32, _: typedesc[E]): bool {.inline.} =
  v >= int32(ord(low(E))) and v <= int32(ord(high(E)))

proc replayCoopFx*(game: var Game) {.moddable.} =
  ## Client: show the host's effects that arrived since the last frame.
  if coopFxInbox.len == 0: return
  let events = coopFxInbox
  coopFxInbox.setLen(0)
  coopFxInboxSnaps = 0
  let pool = game.particlePool
  for ev in events:
    let mine = ev.slot < 0 or ev.slot == localSlot
    let at = Vector2(x: ev.x, y: ev.y)
    let count = int(clamp(ev.a, 0'i32, MaxFxParticles))
    let radius = clamp(ev.z, 0'f32, MaxFxRadius)
    case ev.kind
    of fxSound:
      if enumOk(ev.a, SoundType):
        playSound(SoundType(ev.a),
                  clamp(ev.x, 0'f32, 4'f32) * (if mine: 1'f32 else: TeammateSoundVolume),
                  clamp(ev.y, 0.1'f32, 4'f32))
    of fxShake:
      if mine and enumOk(ev.a, ShakeIntensity):
        addShake(game.dopamine.screenShake, ShakeIntensity(ev.a), ev.color)
    of fxExplosion: spawnExplosionPooled(pool, ev.x, ev.y, ev.color, count)
    of fxTrail: spawnTrailParticlePooled(pool, ev.x, ev.y, ev.color, min(count, 40))
    of fxSparkRing: spawnShockwavePooled(pool, ev.x, ev.y, radius)
    of fxExplosiveRing: spawnExplosiveRingPooled(pool, ev.x, ev.y, radius, min(count, 16), ev.color)
    of fxSpiral: spawnSpiralExplosionPooled(pool, ev.x, ev.y, radius, min(count, 24), ev.color)
    of fxNova: spawnNovaExplosionPooled(pool, ev.x, ev.y, radius, ev.color, ev.color2)
    of fxDeathBurst:
      spawnEnemyDeathBurst(pool, ev.x, ev.y, ev.color, min(radius, 400'f32), ev.a == 1)
    of fxShotParticles:
      if enumOk(ev.a, ParticleSkinType):
        spawnShootingParticles(pool, ev.x, ev.y, Vector2(x: ev.z, y: ev.w),
                               ParticleSkinType(ev.a), game.time)
    of fxPlayerDeath: spawnPlayerDeathExplosion(game, at)
    of fxFizzle: blastFreeFizzle(game, at, ev.color)
    of fxDamage:
      if enumOk(ev.b, DamageType):
        showDamage(game, at, ev.z, (ev.a and 1) != 0, (ev.a and 2) != 0, DamageType(ev.b))
    of fxCurrency:
      if enumOk(ev.b, CurrencyIndicatorKind):
        showCurrency(game, at, int(ev.a), CurrencyIndicatorKind(ev.b))
    of fxPerk: showPerk(game, at, ev.text, ev.color)
    of fxLightning: spawnLightningBolt(game, at, Vector2(x: ev.z, y: ev.w), ev.color)
    of fxBlastRing: spawnShockwaveRing(game, at, radius, ev.color)
    of fxPathBlast:
      if ev.points.len <= 256:
        spawnPathShockwave(game, ev.points, radius, ev.color)
    of fxInstallCard:
      if ev.d == localSlot and enumOk(ev.a, PowerUpType) and enumOk(ev.c, PowerUpRarity):
        showInstallCard(game, PowerUp(powerType: PowerUpType(ev.a), level: int(ev.b),
                                      rarity: PowerUpRarity(ev.c)))
    of fxDamage3D:
      if not activeWorld3D.isNil:
        spawnDamageNumber3D(activeWorld3D.damageNumbers, Vector3(x: ev.x, y: ev.y, z: ev.z),
                            clamp(ev.w, 0'f32, 1.0e9'f32), ev.color)
    of fxShake3D:
      if mine and not activeWorld3D.isNil:
        activeWorld3D.camera.shakeTime = clamp(ev.x, 0'f32, 5'f32)
    of fxPlayerSignal:
      if enumOk(ev.a, DamageEvent) and ev.b >= 0 and ev.b < game.players.len:
        game.players[ev.b].lastDamageEvent = DamageEvent(ev.a)
