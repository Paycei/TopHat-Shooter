## Ground pickups: coins (coin.nim), XP orbs (xp_orb.nim) and consumables
## (consumable.nim, with their effect in game.nim's collectPickup).
##
## Each kind keeps its own data, drop rules and effect. This module owns how
## any of them reaches the player -- the aura pull, the magnet, the touch test
## and the loop tying them together -- so the three behave alike and a fix to
## one lands on all of them. A kind plugs into `updatePickups` by defining,
## next to its type (they are looked up where the loop is instantiated):
##
##   pickupAlive(game, p, dt, count): bool  ticks its expiry; false removes it.
##                                          `count` is the list's length.
##   pickupTrail(p): Color                  the sparkle left while it is pulled
##   collectPickup(game, p): bool           the player touched it: a mod's
##                                          pickup hook, else its effect. True
##                                          only for the boss wave's coin.

import raylib
import modding/mod_patch_core
import particle_types, types, particle_pool, patches

const
  LootMargin* = 50.0'f32       ## drops stay this far inside the arena edge
  PullBaseSpeed = 300.0'f32    ## pull speed at the edge of the aura, px/s
  PullSnapSpeed = 420.0'f32    ## added as the pickup closes in...
  PullSnapRange = 140.0'f32    ## ...over this last stretch

proc clampLootPosition*(x, y: float32, screenWidth, screenHeight: int32): tuple[x, y: float32] {.moddable.} =
  ## A drop point kept LootMargin inside the arena, so loot from an enemy that
  ## died off-screen can still be reached.
  result.x = clamp(x, LootMargin, screenWidth.float32 - LootMargin)
  result.y = clamp(y, LootMargin, screenHeight.float32 - LootMargin)

proc pullTowardPlayer*(pos: var Vector2, playerPos: Vector2, dt: float32) {.moddable.} =
  ## Accelerating pull: a pickup starts drifting and then snaps home. A flat
  ## 300 px/s was slower than a boosted player, so pulled pickups could trail
  ## forever without ever being collected. Scaling with proximity also gives
  ## the pickup a satisfying "click" at the end instead of a constant slide.
  let toPlayer = playerPos - pos
  let dist = max(1.0'f32, toPlayer.length())
  let pullSpeed = PullBaseSpeed + PullSnapSpeed * (1.0'f32 - min(1.0'f32, dist / PullSnapRange))
  pos = pos + toPlayer.normalize() * pullSpeed * dt

proc magnetPullsAll*(player: Player): bool {.moddable.} =
  ## The Magnet consumable or the Garbage Collector patch: every pickup on the
  ## floor homes in, not only the ones inside the collection aura.
  player.magnetTimer > 0 or hasPatch(player, rrtGarbageCollector)

proc updatePickups*[T: Coin | XpOrb | Consumable](game: Game, items: var seq[T], dt: float32): bool =
  ## Expiry, aura/magnet pull and pickup for one kind's list. True when a
  ## collected pickup was the boss wave's coin (completeBossWave is due).
  mixin pickupAlive, pickupTrail, collectPickup
  let count = items.len
  let magnetAll = magnetPullsAll(game.player)
  var i = 0
  while i < items.len:
    let p = items[i]
    if not pickupAlive(game, p, dt, count):
      items.delete(i)
      continue
    let inAura = distance(p.pos, game.player.pos) < game.player.auraRadius
    if inAura or magnetAll:
      pullTowardPlayer(p.pos, game.player.pos, dt)
    if inAura:
      spawnTimedParticlesPooled(game.particlePool, p.pos.x, p.pos.y, 18.0, pickupTrail(p), 1, dt)
    if inPickupRange(p.pos, p.radius, game.player):
      if collectPickup(game, p):
        result = true
      items.delete(i)
      continue
    inc i

proc expirePickups*[T: Coin | XpOrb | Consumable](game: Game, items: var seq[T], dt: float32) =
  ## Expiry alone, for when nothing may be collected (the death sequence).
  mixin pickupAlive
  let count = items.len
  var i = 0
  while i < items.len:
    if pickupAlive(game, items[i], dt, count):
      inc i
    else:
      items.delete(i)
