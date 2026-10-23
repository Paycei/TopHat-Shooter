import raylib, math, random
import modding/mod_patch_core
import draw_prims
import particle_types, types, particle_pool, pickup, sound, powerup, particle, enemy_config
import modding/mod_hooks

## Experience orbs for the run-leveling modes (wave, roguelite + time-survival).
## XP orbs drop on enemy death, reach the player like every ground pickup
## (pickup.nim: the collection aura, the magnet), and on pickup add to the
## player's run XP. It imports only low-level modules and NEVER imports `game`
## (game.nim sits above it and wires it into the frame loop).

const
  XpBaseToLevel* = 10      # XP needed to clear level 1
  XpPerLevelStep* = 6      # added to the threshold for each subsequent level
  XpLongRunQuadratic* = 4  ## `longRun` curve: extra cost per level, squared.
                           ## This carries wave mode's density normalisation on
                           ## its own. Orbs drop at full value so every kill
                           ## still pays out visibly; levels get more expensive
                           ## instead, which lands ~19 levels over a 60-wave run
                           ## rather than the ~67 an unnormalised curve produced.
                           ## Solved against the actual per-wave XP income, so
                           ## retuning calculateWaveEnemyCount means re-solving
                           ## this. Roguelite/survival never apply it.
  XpSurvivalBase* = 12     ## Time Survival curve: 12 + 8n + 1.5n^2. A strong
  XpSurvivalStep* = 8      ## build lands ~200 kills a minute in Boot and ~500 in
  XpSurvivalQuadratic2* = 3 ## Kernel Panic (~7k by 20:00, measured headless);
                           ## with every orb collected that solves to roughly
                           ## levels 11 / 19 / 24 / 29 at 5 / 10 / 15 / 20
                           ## minutes, a few fewer for real orb pickup. The
                           ## quadratic is in halves (3 = 1.5). Re-solve it if
                           ## the density targets in survival.nim change.
  XpRogueliteBase* = 18    ## Roguelite curve: cost of the first level...
  XpRogueliteStep* = 15    ## ...and the linear step after it. Sectors fight on
                           ## the wave-mode swarm curve (dungeonDensityWave), so
                           ## a run has banked ~160 / 480 / 1010 / 1800 XP by the
                           ## end of sectors 1..4 at Heat 1; this lands ~4 / 7.5
                           ## / 11 / 15 levels (18n + 7.5n(n-1) XP for n levels).
                           ## Re-solve it if the room budgets change.
  XpOrbLifetime = 18.0     # seconds before an uncollected orb fades out

proc xpRequiredForLevel*(level: int, mode: GameMode): int {.moddable.} =
  ## XP to clear `level`, per mode.
  ##
  ## Wave mode adds a quadratic term: it runs for dozens of waves, and because
  ## levels grow with the SQUARE ROOT of total XP, even a fully
  ## density-normalised XP income still produced ~37 levels there. Each level is
  ## a power-up draft and a permanent stat bundle, so that alone outpaced every
  ## other progression channel combined.
  ##
  ## Roguelite has its own, steeper linear curve (XpRogueliteBase/-Step), solved
  ## against its swarm-density sectors; Time Survival its own gentle quadratic
  ## against the horde spawner.
  let n = max(0, level - 1)
  let base = case mode
    of gmRoguelite:
      XpRogueliteBase + n * XpRogueliteStep
    of gmWaveBased:
      XpBaseToLevel + n * XpPerLevelStep + n * n * XpLongRunQuadratic
    of gmTimeSurvival:
      XpSurvivalBase + n * XpSurvivalStep + (n * n * XpSurvivalQuadratic2) div 2
    else:
      XpBaseToLevel + n * XpPerLevelStep
  modXpToLevel(base, level, mode)   # mods may reshape the curve (xpToLevel hook)

proc enemyXpValue(enemy: Enemy): int {.moddable.} =
  ## Small per-enemy XP grant, shaped like enemyCoinValue but smaller magnitudes.
  if enemy.isBoss:
    result = 40
  else:
    result = case enemy.enemyType
      of FirstModEnemy..LastModEnemy: modEnemies[enemy.enemyType].xp
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
      of etThread: 1
      of etForkBomb: 2
      of etWatchdog: 2
      of etZombie: 3
      of etDeadlock: 2
      of etDaemon: 3
      of etInterrupt: 1
      of etFragment: 1
      of etPortGuard: 3
      of etSentry: 2
      of etMimic: 3
      of etRestorer: 3
      of etPacket: 2
      of etDriver: 4
      of etCorruptor: 3
      of etEnvironment: 0
  if enemy.isElite:
    result *= 2
  result = modXpValue(enemy, result)

proc newXpOrb*(x, y: float32, value: int = 1): XpOrb {.moddable.} =
  result = XpOrb(
    pos: vec2(x, y),
    radius: 5.0,
    value: value,
    lifetime: XpOrbLifetime
  )

proc pickupAlive*(game: Game, orb: XpOrb, dt: float32, count: int): bool {.moddable.} =
  ## Tick the orb's lifetime; returns false when it should be removed.
  # Roguelite: an orb never expires. Its folder vacuums every orb at clear
  # (collectAllXpOrbs), and a pulsed swarm can leave orbs lying for longer
  # than the lifetime; expiring them silently deleted earned XP.
  if game.mode == gmRoguelite:
    orb.lifetime = max(orb.lifetime, 2.0)
  orb.lifetime -= dt
  orb.lifetime > 0

proc pickupTrail*(orb: XpOrb): Color {.moddable.} =
  Color(r: 90, g: 255, b: 170, a: 150)

proc drawXpOrb(orb: XpOrb) {.moddable.} =
  let t = getTime()
  let pulse = 1.0 + 0.22 * sin(t * 6.0)
  let size = orb.radius * pulse
  # Fade out over the last second of life.
  let fade = clamp(orb.lifetime, 0.0, 1.0)
  let a = uint8(255.0 * fade)
  let glowA = uint8(70.0 * fade)
  # Soft cyan-green glow + bright core (visually distinct from gold coins).
  drawDisc(orb.pos, size + 4 + pulse * 1.5,
             Color(r: 80, g: 255, b: 200, a: glowA))
  drawDisc(orb.pos, size,
             Color(r: 90, g: 255, b: 170, a: a))
  drawDisc(orb.pos, size * 0.5,
             Color(r: 220, g: 255, b: 240, a: a))
  drawCircleOutline(orb.pos.x.int32, orb.pos.y.int32, size,
                  Color(r: 180, g: 255, b: 220, a: a))

proc dataHarvestMultiplier(player: Player): float32 =
  ## DATA_HARVEST.dll: +25% / +50% / +100% XP per enemy at levels 1 / 2 / 3.
  case getPowerUpLevel(player, puDataHarvest)
  of 0: 1.0
  of 1: 1.25
  of 2: 1.5
  else: 2.0

proc dropEnemyXp*(game: Game, enemy: Enemy) {.moddable.} =
  ## Drop XP orb(s) at the dead enemy's position in the run-leveling modes.
  ## Bosses split their lump into a small cluster for a satisfying shower of orbs.
  ##
  ## Wave mode was added to this set deliberately. It previously had NO
  ## second-to-second reward loop at all: every reward was deferred to a wave
  ## boundary, so the actual moment-to-moment game gave the player nothing back
  ## for a kill except a number. Orbs streaming in on every kill are the drip
  ## that the wave-boundary drafts cannot provide.
  if game.mode notin {gmWaveBased, gmRoguelite, gmTimeSurvival}: return
  if enemy.spawnedByBoss: return
  let base = enemyXpValue(enemy)
  if base <= 0: return   # etEnvironment and friends are worth nothing by design
  # EVERY scoring enemy drops an orb. The floor of 1 is load-bearing, not
  # defensive: density normalisation was briefly applied to this VALUE, and
  # because the result is truncated to an int it silently zeroed the drop for
  # every cheap enemy -- circles paid nothing from wave 1, and past wave 40 only
  # snipers and mages dropped at all. That deleted the moment-to-moment feedback
  # the orbs exist to provide.
  #
  # XP is the one reward channel with TWO sides: what an enemy gives and what a
  # level costs. Only the second is a balance lever; the first is feedback. So
  # the density normalisation lives entirely in xpRequiredForLevel's `longRun`
  # curve, which reaches the same level pacing without ever silencing a kill.
  # (Coins, consumables and elites have no matching cost curve, which is why
  # they are normalised on the grant side instead -- see waveDensityRebate.)
  var total = max(1, int(base.float32 * dataHarvestMultiplier(game.player)))
  # Survival's Overclock event doubles XP while it runs.
  if game.mode == gmTimeSurvival and game.survival.xpMult > 1.0'f32:
    total = int(total.float32 * game.survival.xpMult)
  let clamped = clampLootPosition(enemy.pos.x, enemy.pos.y, game.screenWidth, game.screenHeight)
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

proc collectPickup*(game: Game, orb: XpOrb): bool {.moddable.} =
  ## The player touched `orb`: a mod's pickup hook may take it, else its XP
  ## and feedback (the caller removes it).
  if modPickup(game, "xp", orb.value.float64):
    return
  # A co-op team shares its XP: every player still in the run gains it, so
  # they level -- and draft -- together.
  for p in game.players:
    if not p.eliminated: p.xp += orb.value
  playSound(stCoinPickup, 0.35, 1.4)  # higher pitch than coins
  spawnExplosionPooled(game.particlePool, orb.pos.x, orb.pos.y,
                       Color(r: 90, g: 255, b: 170, a: 255), 5)
  # Floating "+N" pickup indicator, mirroring the coin pickup feedback.
  game.currencyIndicators.add(newCurrencyIndicator(
    orb.pos.x, orb.pos.y, orb.value, cikXp))

proc updateGameXpOrbs*(game: Game, dt: float32) {.moddable.} =
  ## Lifetime decay, aura/magnet homing, and pickup (pickup.nim).
  discard updatePickups(game, game.xpOrbs, dt)

proc collectAllXpOrbs*(game: Game) {.moddable.} =
  ## Bank every orb on the floor at once (a roguelite folder clearing), so the
  ## final kills' XP counts toward the level-ups banked right after. Mirrors
  ## coin.nim's collectAllCoins.
  if game.xpOrbs.len == 0: return
  var total = 0
  for orb in game.xpOrbs:
    total += orb.value
  game.xpOrbs = @[]
  if total > 0:
    for p in game.players:   # (shared, as for a single orb)
      if not p.eliminated: p.xp += total
    playSound(stCoinPickup, 0.4, 1.4)
    game.currencyIndicators.add(newCurrencyIndicator(
      game.player.pos.x + 18, game.player.pos.y - 8, total, cikXp))

proc drawGameXpOrbs*(game: Game) {.moddable.} =
  for orb in game.xpOrbs:
    drawXpOrb(orb)
