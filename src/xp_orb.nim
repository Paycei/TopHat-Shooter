import raylib, math, random
import particle_types
import types
import particle_pool, sound, powerup

## Roguelite-only experience orbs. This module is a deliberate sibling of
## `coin.nim`: XP orbs drop on enemy death, auto-home to the player through the
## collection aura (and from anywhere while a Magnet consumable is active), and
## on pickup add to the player's run XP. It imports only low-level modules and
## NEVER imports `game` (game.nim sits above it and wires it into the frame loop).

const
  XpBaseToLevel* = 10      # XP needed to clear level 1
  XpPerLevelStep* = 6      # added to the threshold for each subsequent level
  XpOrbPullSpeed = 320.0   # homing speed in px/s (slightly snappier than coins)
  XpOrbLifetime = 18.0     # seconds before an uncollected orb fades out
  XpLootMargin = 50.0      # keep drops this far from the screen edge (cf. coin.nim)

proc clampXpDrop(x, y: float32, sw, sh: int32): tuple[x, y: float32] =
  result.x = clamp(x, XpLootMargin, sw.float32 - XpLootMargin)
  result.y = clamp(y, XpLootMargin, sh.float32 - XpLootMargin)

proc xpRequiredForLevel*(level: int): int =
  ## Steady, escalating curve: ~one level per room early, slowing later.
  XpBaseToLevel + max(0, level - 1) * XpPerLevelStep

proc enemyXpValue*(enemy: Enemy): int =
  ## Small per-enemy XP grant, shaped like enemyCoinValue but smaller magnitudes.
  if enemy.isBoss:
    result = 40
  else:
    result = case enemy.enemyType
      of etCircle: 1
      of etCube: 2
      of etTriangle: 1
      of etStar: 3
      of etHexagon: 2
      of etCross: 2
      of etDiamond: 2
      of etOctagon: 2
      of etPentagon: 1
      of etTrickster: 3
      of etPhantom: 3
      of etSniper: 4
      of etMage: 4
      of etEnvironment: 0
  if enemy.isElite:
    result *= 2

proc newXpOrb*(x, y: float32, value: int = 1): XpOrb =
  result = XpOrb(
    pos: newVector2f(x, y),
    radius: 5.0,
    value: value,
    lifetime: XpOrbLifetime
  )

proc updateXpOrb*(orb: XpOrb, dt: float32): bool =
  ## Tick the orb's lifetime; returns false when it should be removed.
  orb.lifetime -= dt
  orb.lifetime > 0

proc drawXpOrb*(orb: XpOrb) =
  let t = getTime()
  let pulse = 1.0 + 0.22 * sin(t * 6.0)
  let size = orb.radius * pulse
  # Fade out over the last second of life.
  let fade = clamp(orb.lifetime, 0.0, 1.0)
  let a = uint8(255.0 * fade)
  let glowA = uint8(70.0 * fade)
  # Soft cyan-green glow + bright core (visually distinct from gold coins).
  drawCircle(Vector2(x: orb.pos.x, y: orb.pos.y), size + 4 + pulse * 1.5,
             Color(r: 80, g: 255, b: 200, a: glowA))
  drawCircle(Vector2(x: orb.pos.x, y: orb.pos.y), size,
             Color(r: 90, g: 255, b: 170, a: a))
  drawCircle(Vector2(x: orb.pos.x, y: orb.pos.y), size * 0.5,
             Color(r: 220, g: 255, b: 240, a: a))
  drawCircleLines(orb.pos.x.int32, orb.pos.y.int32, size,
                  Color(r: 180, g: 255, b: 220, a: a))

proc moveXpOrbToPlayer*(orb: XpOrb, playerPos: Vector2f, dt: float32) =
  let dir = (playerPos - orb.pos).normalize()
  orb.pos = orb.pos + dir * XpOrbPullSpeed * dt

proc checkPlayerCollision(orb: XpOrb, player: Player): bool =
  let collectRange = if player.magnetTimer > 0: 80.0 else: orb.radius + player.radius
  distance(orb.pos, player.pos) < collectRange

proc dataHarvestMultiplier(player: Player): float32 =
  ## DATA_HARVEST.dll: +25% / +50% / +100% XP per enemy at levels 1 / 2 / 3.
  case getPowerUpLevel(player, puDataHarvest)
  of 0: 1.0
  of 1: 1.25
  of 2: 1.5
  else: 2.0

proc dropEnemyXp*(game: Game, enemy: Enemy) =
  ## Roguelite-only: drop XP orb(s) at the dead enemy's position. Bosses split
  ## their lump into a small cluster for a satisfying shower of orbs.
  if game.mode != gmRoguelite: return
  if enemy.spawnedByBoss: return
  let total = int(enemyXpValue(enemy).float32 * dataHarvestMultiplier(game.player))
  if total <= 0: return
  let clamped = clampXpDrop(enemy.pos.x, enemy.pos.y, game.screenWidth, game.screenHeight)
  if enemy.isBoss:
    # Spread the boss XP across several orbs around the death point.
    const orbCount = 8
    let per = max(1, total div orbCount)
    for _ in 0..<orbCount:
      let ang = rand(1.0) * PI * 2.0
      let dist = 10.0 + rand(40.0)
      let ox = clamp(clamped.x + cos(ang) * dist, 0.0'f32, game.screenWidth.float32)
      let oy = clamp(clamped.y + sin(ang) * dist, 0.0'f32, game.screenHeight.float32)
      game.xpOrbs.add(newXpOrb(ox, oy, per))
  else:
    game.xpOrbs.add(newXpOrb(clamped.x, clamped.y, total))

proc updateGameXpOrbs*(game: Game, dt: float32) =
  ## Lifetime decay, aura/magnet homing, and pickup. Mirrors updateGameCoins.
  var i = 0
  while i < game.xpOrbs.len:
    if not updateXpOrb(game.xpOrbs[i], dt):
      game.xpOrbs.delete(i)
      continue

    # Auto-home when inside the collection aura, or anywhere while Magnet is up.
    if distance(game.xpOrbs[i].pos, game.player.pos) < game.player.auraRadius:
      moveXpOrbToPlayer(game.xpOrbs[i], game.player.pos, dt)
      spawnTimedParticlesPooled(game.particlePool, game.xpOrbs[i].pos.x, game.xpOrbs[i].pos.y,
                         18.0, Color(r: 90, g: 255, b: 170, a: 150), 1, dt)
    if game.player.magnetTimer > 0:
      moveXpOrbToPlayer(game.xpOrbs[i], game.player.pos, dt)

    if checkPlayerCollision(game.xpOrbs[i], game.player):
      game.player.xp += game.xpOrbs[i].value
      playSound(stCoinPickup, 0.35, 1.4)  # higher pitch than coins
      spawnExplosionPooled(game.particlePool, game.xpOrbs[i].pos.x, game.xpOrbs[i].pos.y,
                           Color(r: 90, g: 255, b: 170, a: 255), 5)
      game.xpOrbs.delete(i)
      continue

    i += 1

proc drawGameXpOrbs*(game: Game) =
  for orb in game.xpOrbs:
    drawXpOrb(orb)
