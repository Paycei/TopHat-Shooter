## Dungeon crawler core for the roguelite mode.
##
## A run is 4 themed floors drawn from a 7-theme pool. Each floor is a grid of
## screen-sized rooms connected by doors at the screen-edge midpoints. Combat
## rooms lock their doors and spawn one pre-rolled encounter; clearing the room
## opens the doors again. The boss room ends the floor.
##
## This module owns floor generation, themes, room transitions, and pickups.
## It must NOT import game.nim (game.nim imports this module); enemy spawning
## itself stays in game.nim and only reads the counters/state armed here.

import raylib, random, math, tables
import gamepad_input, particle_types, types, roguelite, powerup, particle, sound, localization, boss_definitions, settings, coin, utils

const
  DoorZoneWidth* = 120'f32   # Length of the door opening along the edge
  DoorZoneDepth* = 34'f32    # How far the door zone reaches into the room
  DungeonGridSize* = 6       # Logical floor grid (6x6)
  ShopTerminalRadius* = 52'f32
  PickupRadius* = 26'f32
  ExitPortalRadius* = 48'f32           # Player-entry radius of the boss-clear portal
  ExitPortalSpawnDuration* = 1.1'f32   # Spawn animation length before it becomes enterable
  RoomTransitionDuration* = 0.35'f32
  CombatObstacleHp* = 4'f32          # Floor-1 combat obstacle HP; a kiting crowd chips these down
  BossObstacleHp* = 6'f32            # Floor-1 boss obstacle HP; adds chip them, the boss one-shots
  CombatObstacleHpPerFloor* = 2'f32  # Added per floor (and per endless loop) so late walls hold up
  BossObstacleHpPerFloor* = 3'f32    # Added per floor (and per endless loop)
  BossWallRespawnDelay* = 8'f32      # Seconds a smashed boss-room obstacle stays gone

type
  DungeonThemeDef* = object
    accent*: Color
    ## Roster entries unlock progressively: an enemy only spawns once the
    ## room's effective threat reaches its minThreat. Enemy base configs are
    ## tuned for their wave-mode introduction points (a Pentagon has 10 base
    ## HP, a Mage 20), so early rooms must stick to the cheap types.
    roster*: seq[tuple[enemy: EnemyType, weight: int, minThreat: int]]
    bossNumber*: int          # Index into boss_definitions
    pressureMod*: float32     # Scales encounter difficulty
    eliteBonus*: int          # Added to the elite-chance roll input
    shardMod*: float32        # Scales shard rewards
    obstacleMin*, obstacleMax*: int

  DungeonClearOutcome* = enum
    dcoNone,
    dcoDraft

# ---------------------------------------------------------------------------
# Themes

proc themeDef*(theme: DungeonFloorTheme): DungeonThemeDef =
  # Threat reference (heat 1): floor 1 rooms sit around threat 1-5,
  # floor 2 ~6-12, floor 3 ~11-17, floor 4 ~16-23.
  # Gates are intentionally light: complex types are welcome early because
  # tuneDungeonEnemyStats compresses their stats toward the room's threat.
  case theme
  of dftFirewall:
    DungeonThemeDef(
      accent: Color(r: 255, g: 110, b: 48, a: 255),
      roster: @[(etCircle, 28, 0), (etCube, 26, 0), (etPentagon, 26, 2),
                (etOctagon, 20, 4)],
      bossNumber: 3, pressureMod: 1.0, eliteBonus: 0, shardMod: 1.0,
      obstacleMin: 2, obstacleMax: 4)
  of dftRecycleBin:
    DungeonThemeDef(
      accent: Color(r: 150, g: 190, b: 140, a: 255),
      roster: @[(etCircle, 45, 0), (etTriangle, 35, 0), (etStar, 20, 2)],
      bossNumber: 2, pressureMod: 0.95, eliteBonus: 0, shardMod: 1.0,
      obstacleMin: 3, obstacleMax: 5)
  of dftRegistry:
    DungeonThemeDef(
      accent: Color(r: 90, g: 160, b: 255, a: 255),
      roster: @[(etCube, 26, 0), (etCross, 26, 0), (etPentagon, 24, 2),
                (etDiamond, 22, 4)],
      bossNumber: 4, pressureMod: 1.05, eliteBonus: 2, shardMod: 1.1,
      obstacleMin: 3, obstacleMax: 5)
  of dftNetwork:
    DungeonThemeDef(
      accent: Color(r: 0, g: 220, b: 255, a: 255),
      roster: @[(etCircle, 22, 0), (etTriangle, 32, 0), (etDiamond, 28, 2),
                (etSniper, 16, 5)],
      bossNumber: 7, pressureMod: 1.1, eliteBonus: 3, shardMod: 1.15,
      obstacleMin: 1, obstacleMax: 3)
  of dftKernel:
    DungeonThemeDef(
      accent: Color(r: 150, g: 95, b: 235, a: 255),
      roster: @[(etCube, 24, 0), (etOctagon, 26, 0), (etStar, 30, 2),
                (etMage, 20, 5)],
      bossNumber: 8, pressureMod: 1.18, eliteBonus: 4, shardMod: 1.25,
      obstacleMin: 2, obstacleMax: 4)
  of dftCache:
    DungeonThemeDef(
      accent: Color(r: 70, g: 215, b: 195, a: 255),
      roster: @[(etHexagon, 32, 0), (etTrickster, 34, 0), (etPhantom, 34, 3)],
      bossNumber: 5, pressureMod: 1.12, eliteBonus: 3, shardMod: 1.2,
      obstacleMin: 2, obstacleMax: 4)
  of dftCorruptedSector:
    DungeonThemeDef(
      accent: Color(r: 255, g: 80, b: 200, a: 255),
      roster: @[(etCircle, 12, 0), (etTriangle, 12, 0), (etCube, 10, 0),
                (etHexagon, 6, 0), (etPentagon, 10, 2), (etStar, 10, 2),
                (etCross, 10, 2), (etDiamond, 10, 4), (etOctagon, 10, 4),
                (etTrickster, 6, 4), (etPhantom, 6, 6), (etSniper, 4, 6),
                (etMage, 4, 8)],
      bossNumber: 11, pressureMod: 1.3, eliteBonus: 8, shardMod: 1.45,
      obstacleMin: 3, obstacleMax: 5)

proc themeKey(theme: DungeonFloorTheme): string =
  case theme
  of dftFirewall: "firewall"
  of dftRecycleBin: "recycle_bin"
  of dftRegistry: "registry"
  of dftNetwork: "network"
  of dftKernel: "kernel"
  of dftCache: "cache"
  of dftCorruptedSector: "corrupted_sector"

proc themeName*(theme: DungeonFloorTheme): string =
  t("dungeon_theme_" & themeKey(theme))

proc themeDescription*(theme: DungeonFloorTheme): string =
  t("dungeon_theme_" & themeKey(theme) & "_desc")

proc themeAccent*(theme: DungeonFloorTheme): Color =
  themeDef(theme).accent

# ---------------------------------------------------------------------------
# Grid helpers

proc opposite*(dir: DoorDir): DoorDir =
  case dir
  of ddUp: ddDown
  of ddDown: ddUp
  of ddLeft: ddRight
  of ddRight: ddLeft

proc gridDelta(dir: DoorDir): tuple[dx, dy: int] =
  case dir
  of ddUp: (0, -1)
  of ddDown: (0, 1)
  of ddLeft: (-1, 0)
  of ddRight: (1, 0)

proc roomAt(floor: DungeonFloor, gx, gy: int): int =
  ## Index of the room at grid cell, or -1.
  for i, room in floor.rooms:
    if room.gridX == gx and room.gridY == gy:
      return i
  -1

proc neighborIndex*(floor: DungeonFloor, roomIdx: int, dir: DoorDir): int =
  let (dx, dy) = gridDelta(dir)
  let room = floor.rooms[roomIdx]
  floor.roomAt(room.gridX + dx, room.gridY + dy)

proc currentDungeonRoom*(run: RogueliteRun): DungeonRoom =
  if run.isNil or run.floor.isNil or run.floor.rooms.len == 0:
    return nil
  run.floor.rooms[run.floor.currentRoom]

proc doorRect*(game: Game, dir: DoorDir): Rectangle =
  let w = game.screenWidth.float32
  let h = game.screenHeight.float32
  case dir
  of ddUp:
    Rectangle(x: w / 2 - DoorZoneWidth / 2, y: 0,
              width: DoorZoneWidth, height: DoorZoneDepth)
  of ddDown:
    Rectangle(x: w / 2 - DoorZoneWidth / 2, y: h - DoorZoneDepth,
              width: DoorZoneWidth, height: DoorZoneDepth)
  of ddLeft:
    Rectangle(x: 0, y: h / 2 - DoorZoneWidth / 2,
              width: DoorZoneDepth, height: DoorZoneWidth)
  of ddRight:
    Rectangle(x: w - DoorZoneDepth, y: h / 2 - DoorZoneWidth / 2,
              width: DoorZoneDepth, height: DoorZoneWidth)

proc doorSpawnPos*(game: Game, enteredThrough: DoorDir): Vector2f =
  ## Where the player appears after arriving through the given door.
  let w = game.screenWidth.float32
  let h = game.screenHeight.float32
  const inset = 86'f32
  case enteredThrough
  of ddUp: newVector2f(w / 2, inset)
  of ddDown: newVector2f(w / 2, h - inset)
  of ddLeft: newVector2f(inset, h / 2)
  of ddRight: newVector2f(w - inset, h / 2)

# ---------------------------------------------------------------------------
# Difficulty

proc dungeonEffectiveThreat*(run: RogueliteRun, room: DungeonRoom): int =
  let heatRank = heatChallengeRank(run.heat)
  (run.floorNumber - 1) * 5 + room.bfsDepth +
    heatRank * RogueliteHeatRosterWaveOffset + run.endlessLoop * 10

proc dungeonEnemyDifficulty*(run: RogueliteRun, room: DungeonRoom): float32 =
  let def = themeDef(run.floor.theme)
  let heatRank = heatChallengeRank(run.heat)
  dungeonEffectiveThreat(run, room).float32 / 4.0'f32 * def.pressureMod +
    heatRank.float32 * RogueliteHeatDifficultyPerTier +
    run.endlessLoop.float32 * 1.0'f32

proc dungeonRoomWaveEquivalent*(run: RogueliteRun, room: DungeonRoom): float32 =
  ## Maps room threat onto the wave-mode scale (floor 1 plays like waves 2-12,
  ## floor 4 like the wave-mode late game). Used to calibrate stat compression
  ## and elite stat magnitudes against the wave-tuned numbers.
  dungeonEffectiveThreat(run, room).float32 * 2.5'f32

proc dungeonEliteRoll*(run: RogueliteRun, room: DungeonRoom): int =
  ## CHANCE input for makeElite only - the +30 elite-room boost guarantees
  ## frequent elites there, but stat magnitudes come from the room's wave
  ## equivalent (passed separately as makeElite's scalingWave).
  let def = themeDef(run.floor.theme)
  var roll = dungeonEffectiveThreat(run, room) + def.eliteBonus
  if room.kind == drkElite:
    roll += 30
  roll

proc enemyTuningWave(enemyType: EnemyType): float32 =
  ## The wave-mode introduction wave each type's base config is balanced for
  ## (see the roster table in spawnWaveEnemies). A type spawning far below
  ## this point needs its stats compressed.
  case enemyType
  of etCircle: 1
  of etPentagon: 6
  of etTriangle: 11
  of etCube: 16
  of etStar: 21
  of etCross: 26
  of etDiamond: 31
  of etOctagon: 36
  of etHexagon: 41
  of etTrickster: 46
  of etSniper: 50
  of etPhantom: 51
  of etMage: 56
  of etEnvironment: 1

proc tuneDungeonEnemyStats*(enemy: Enemy, run: RogueliteRun, room: DungeonRoom) =
  ## Enemy base configs assume the player power of their wave-mode intro point
  ## (a Mage expects a wave-56 build). The dungeon spawns any type anywhere,
  ## so compress HP/hit-count fully and damage more gently toward the room's
  ## wave-equivalent threat. Past the tuning point, stats are left alone.
  let introWave = enemyTuningWave(enemy.enemyType)
  let waveEquivalent = dungeonRoomWaveEquivalent(run, room)
  if waveEquivalent >= introWave:
    return
  let factor = clamp(waveEquivalent / introWave, 0.22'f32, 1.0'f32)
  enemy.hp = max(0.5'f32, enemy.hp * factor)
  enemy.maxHp = enemy.hp
  if enemy.requiredHits > 0:
    enemy.requiredHits = max(2, int(enemy.requiredHits.float32 * factor))
  # Contact damage compresses gently (it needs a touch to land); ranged damage
  # compresses with the full factor because bullets are the spammy threat.
  enemy.contactDamage *= clamp(sqrt(factor), 0.45'f32, 1.0'f32)
  let rangedFactor = clamp(factor, 0.3'f32, 1.0'f32)
  enemy.rangedDamage *= rangedFactor
  # Special attacks that read config values directly (mage meteorites, etc.)
  # apply this factor at their own creation sites.
  enemy.damageTuning = rangedFactor

proc dungeonBossDifficulty*(run: RogueliteRun): float32 =
  let def = themeDef(run.floor.theme)
  let heatRank = heatChallengeRank(run.heat)
  run.floorNumber.float32 * 1.1'f32 * def.pressureMod +
    heatRank.float32 * RogueliteHeatBossDifficultyPerTier +
    run.endlessLoop.float32 * 1.5'f32

proc dungeonBossBand*(floorNumber: int): tuple[lo, hi: int] =
  ## Non-overlapping per-floor boss bands. The latest floor is reserved for the
  ## 12th (final) boss alone; bosses 1..11 are spread across the earlier floors,
  ## so only the starter bosses can headline floor 1 and only the final boss can
  ## appear on the last floor. Assumes the 4-floor / 12-boss layout.
  if floorNumber >= RogueliteFloorsToWin:
    (12, 12)
  else:
    case floorNumber
    of 1: (1, 3)
    of 2: (4, 7)
    else: (8, 11)

proc themeBossRank(theme: DungeonFloorTheme): tuple[rank, count: int] =
  ## Difficulty rank of a theme among all themes, ordered by its authored
  ## bossNumber (0 = easiest theme). Used to spread the themes evenly across a
  ## floor's boss band instead of clamping their raw bossNumber (which saturates
  ## every harder theme onto the band's top boss).
  let mine = themeDef(theme).bossNumber
  var rank = 0
  var count = 0
  for th in DungeonFloorTheme:
    inc count
    if themeDef(th).bossNumber < mine:
      inc rank
  (rank, count)

proc dungeonBossNumberFor*(theme: DungeonFloorTheme,
                           floorNumber, endlessLoop, unlockedBossTier: int): int =
  ## Boss that will headline `floorNumber` for `theme`. The theme's difficulty
  ## rank is mapped proportionally across the floor's exclusive band (see
  ## dungeonBossBand) so each floor spans its whole boss range, then the unlocked
  ## tier and endless loop nudge it up within the band. Pure so the floor-select
  ## preview can call it before the floor itself is generated.
  let band = dungeonBossBand(floorNumber)
  let span = band.hi - band.lo
  let (rank, count) = themeBossRank(theme)
  let themePos = if span <= 0 or count <= 1: 0
                 else: int(round(rank.float32 / (count - 1).float32 * span.float32))
  # Wrap the tier/endless nudge *within* the band instead of clamping it. Adding a
  # flat offset and clamping saturates every theme onto band.hi the moment the
  # offset reaches the span (e.g. boss tier 3 on floor 1, span 2), collapsing all
  # three theme cards onto a single boss. A modular shift preserves the number of
  # distinct bosses the rank spread produced at tier 1, so generateThemeChoices
  # still has distinct boss-groups to draw three different cards from. (Tier/loop
  # difficulty is applied to the boss's *stats* in tuneDungeonBossStats, not to
  # which boss number headlines the floor.)
  let slots = span + 1
  if slots <= 1: band.lo
  else: band.lo + ((themePos + (unlockedBossTier - 1) + endlessLoop) mod slots)

proc unlockedBossTierOf*(game: Game): int =
  ## Boss tier from the active profile (1 when there is no profile yet).
  if game.rogueliteProfile != nil: game.rogueliteProfile.unlockedBossTier else: 1

proc dungeonBossNumber*(game: Game): int =
  let run = game.rogueliteRun
  dungeonBossNumberFor(run.floor.theme, run.floorNumber, run.endlessLoop,
                       unlockedBossTierOf(game))

proc dungeonBossWaveEquivalent(run: RogueliteRun): float32 =
  ## The wave-mode boss slot a floor boss should feel like: floor 1 plays like
  ## the wave-5 boss fight, floor 4 like wave ~35, pushed up by heat/endless.
  let heatRank = heatChallengeRank(run.heat)
  5.0'f32 + (run.floorNumber - 1).float32 * 10.0'f32 +
    heatRank.float32 * 5.0'f32 + run.endlessLoop.float32 * 15.0'f32

proc tuneDungeonBossStats*(boss: Enemy, run: RogueliteRun) =
  ## Boss base stats grow steeply with their number (boss 1: 125 base HP,
  ## boss 12: 3500), so proportional compression can't bridge the gap when a
  ## themed late-number boss appears on an early floor. Instead, normalize the
  ## spawned boss to the HP/damage *budget* of the boss that would naturally
  ## hold this floor's wave slot - it keeps its mechanics, phases, and weak
  ## points, but fights with floor-appropriate numbers. Attack damage flows
  ## through damageTuning, applied in executeCustomBossAttack.
  if boss.isNil or not boss.isBoss or run.isNil:
    return
  let waveEquivalent = dungeonBossWaveEquivalent(run)
  let budgetNumber = clamp(int(round(waveEquivalent / 5.0'f32)), 1, 12)
  if budgetNumber >= boss.bossDefinitionID:
    boss.damageTuning = 1.0
    return
  let actualDef = getBossDefinition(boss.bossDefinitionID)
  let budgetDef = getBossDefinition(budgetNumber)

  # Same growth curve as getScaledBossHP, anchored at the floor's wave slot.
  let waveScale = 1.0'f32 +
    max(0.0'f32, (waveEquivalent - 5.0'f32) / 5.0'f32) * 0.2'f32
  let targetHp = budgetDef.baseHP * waveScale
  if boss.bossTotalMaxHp > 0:
    let hpFactor = clamp(targetHp / boss.bossTotalMaxHp, 0.02'f32, 1.0'f32)
    boss.hp *= hpFactor
    boss.maxHp *= hpFactor
    boss.bossTotalMaxHp *= hpFactor
    for i in 0..<boss.bossPhaseHpPools.len:
      boss.bossPhaseHpPools[i] *= hpFactor

  let damageFactor = clamp(
    budgetDef.baseDamage.float32 / max(1.0'f32, actualDef.baseDamage.float32),
    0.25'f32, 1.0'f32)
  boss.contactDamage *= damageFactor
  boss.rangedDamage *= damageFactor
  boss.damageTuning = damageFactor

proc rollEncounterEnemyType*(run: RogueliteRun, room: DungeonRoom): EnemyType =
  ## Weighted pick from the floor theme's roster (non-deterministic on purpose:
  ## the budget is pre-rolled, the composition order is not). Entries above the
  ## room's threat are excluded so early rooms only see the cheap types.
  let def = themeDef(run.floor.theme)
  let threat = dungeonEffectiveThreat(run, room)
  var total = 0
  for entry in def.roster:
    if entry.minThreat <= threat:
      total += entry.weight
  if total <= 0:
    # Nothing unlocked yet: fall back to the theme's most basic enemy.
    var best = def.roster[0]
    for entry in def.roster:
      if entry.minThreat < best.minThreat:
        best = entry
    return best.enemy
  var roll = rand(total - 1)
  for entry in def.roster:
    if entry.minThreat > threat:
      continue
    roll -= entry.weight
    if roll < 0:
      return entry.enemy
  def.roster[0].enemy

# ---------------------------------------------------------------------------
# Floor generation

proc floorRoomTarget(floorNumber: int): int =
  case max(1, floorNumber)
  of 1: 8
  of 2: 9
  of 3: 11
  else: 12

proc computeDoors(floor: DungeonFloor) =
  for i, room in floor.rooms:
    room.doors = {}
    for dir in DoorDir:
      if floor.neighborIndex(i, dir) >= 0:
        room.doors.incl(dir)

proc computeDepths(floor: DungeonFloor) =
  for room in floor.rooms:
    room.bfsDepth = -1
  floor.rooms[floor.startIdx].bfsDepth = 0
  var queue = @[floor.startIdx]
  var head = 0
  while head < queue.len:
    let idx = queue[head]
    inc head
    for dir in floor.rooms[idx].doors:
      let n = floor.neighborIndex(idx, dir)
      if n >= 0 and floor.rooms[n].bfsDepth < 0:
        floor.rooms[n].bfsDepth = floor.rooms[idx].bfsDepth + 1
        queue.add(n)

proc isolateAsDeadEnd(floor: DungeonFloor, idx: int) =
  ## Keep only the door toward the lowest-depth neighbor; remove the others
  ## symmetrically so the room becomes a proper dead end.
  var bestDir = ddUp
  var bestDepth = int.high
  for dir in floor.rooms[idx].doors:
    let n = floor.neighborIndex(idx, dir)
    if n >= 0 and floor.rooms[n].bfsDepth < bestDepth:
      bestDepth = floor.rooms[n].bfsDepth
      bestDir = dir
  for dir in DoorDir:
    if dir != bestDir and dir in floor.rooms[idx].doors:
      let n = floor.neighborIndex(idx, dir)
      floor.rooms[idx].doors.excl(dir)
      if n >= 0:
        floor.rooms[n].doors.excl(opposite(dir))

proc neighborCount(floor: DungeonFloor, idx: int): int =
  for dir in floor.rooms[idx].doors:
    if floor.neighborIndex(idx, dir) >= 0:
      inc result

proc centerPickup(game: Game, kind: DungeonPickupKind, cost: int = 0,
                  offsetX: float32 = 0, offsetY: float32 = 0): DungeonPickup =
  DungeonPickup(
    pos: newVector2f(game.screenWidth.float32 / 2 + offsetX,
                     game.screenHeight.float32 / 2 + offsetY),
    kind: kind,
    costCredits: cost,
    taken: false
  )

proc generateFloor*(game: Game, theme: DungeonFloorTheme, floorNumber: int): DungeonFloor =
  let run = game.rogueliteRun
  var rng = initRand(run.seed + floorNumber * 7919 + run.endlessLoop * 104729)
  let target = floorRoomTarget(floorNumber)
  let heatRank = heatChallengeRank(run.heat)

  result = DungeonFloor(
    theme: theme,
    floorNumber: floorNumber,
    rooms: @[],
    currentRoom: 0,
    startIdx: 0,
    bossIdx: 0,
    mapRevealed: false,
    compassFound: false
  )

  # Random-walk placement on the grid, biased toward cells that touch only
  # one existing room so the layout grows corridors and dead ends.
  let center = DungeonGridSize div 2
  result.rooms.add(DungeonRoom(gridX: center, gridY: center, kind: drkStart))
  while result.rooms.len < target:
    var candidates: seq[tuple[gx, gy: int]] = @[]
    var weights: seq[int] = @[]
    for room in result.rooms:
      for dir in DoorDir:
        let (dx, dy) = gridDelta(dir)
        let gx = room.gridX + dx
        let gy = room.gridY + dy
        if gx < 0 or gy < 0 or gx >= DungeonGridSize or gy >= DungeonGridSize:
          continue
        if result.roomAt(gx, gy) >= 0:
          continue
        var touching = 0
        for d2 in DoorDir:
          let (dx2, dy2) = gridDelta(d2)
          if result.roomAt(gx + dx2, gy + dy2) >= 0:
            inc touching
        var already = false
        for c in candidates:
          if c.gx == gx and c.gy == gy:
            already = true
            break
        if not already:
          candidates.add((gx, gy))
          weights.add(if touching == 1: 4 else: 1)
    if candidates.len == 0:
      break
    var total = 0
    for w in weights: total += w
    var roll = rng.rand(total - 1)
    var pick = 0
    for i, w in weights:
      roll -= w
      if roll < 0:
        pick = i
        break
    result.rooms.add(DungeonRoom(gridX: candidates[pick].gx,
                                 gridY: candidates[pick].gy, kind: drkCombat))

  computeDoors(result)
  computeDepths(result)

  # Boss room: the farthest room from start, forced into a dead end.
  var bossIdx = 0
  var bestScore = -1
  for i, room in result.rooms:
    if i == result.startIdx: continue
    # Prefer existing dead ends at equal depth
    let score = room.bfsDepth * 10 + (if neighborCount(result, i) == 1: 5 else: 0)
    if score > bestScore:
      bestScore = score
      bossIdx = i
  result.bossIdx = bossIdx
  result.rooms[bossIdx].kind = drkBoss
  isolateAsDeadEnd(result, bossIdx)
  computeDepths(result)

  # Treasure room: farthest remaining dead end; locked behind a key.
  var treasureIdx = -1
  bestScore = -1
  for i, room in result.rooms:
    if i == result.startIdx or i == bossIdx: continue
    if neighborCount(result, i) != 1: continue
    if room.bfsDepth > bestScore:
      bestScore = room.bfsDepth
      treasureIdx = i
  if treasureIdx >= 0:
    result.rooms[treasureIdx].kind = drkTreasure
    result.rooms[treasureIdx].locked = true
    result.rooms[treasureIdx].pickups.add(centerPickup(game, dpkRelicPedestal))
    result.rooms[treasureIdx].pickups.add(
      centerPickup(game, dpkShardCache, offsetX = 70))

  # Shop room: mid-depth room that isn't already special.
  var shopIdx = -1
  var bestShopScore = -1
  let maxDepth = result.rooms[bossIdx].bfsDepth
  for i, room in result.rooms:
    if i == result.startIdx or i == bossIdx or i == treasureIdx: continue
    let mid = abs(room.bfsDepth - maxDepth div 2)
    let score = 100 - mid * 10 + (if neighborCount(result, i) == 1: 8 else: 0)
    if score > bestShopScore:
      bestShopScore = score
      shopIdx = i
  if shopIdx >= 0:
    result.rooms[shopIdx].kind = drkShop
    # The floor map is sold in the shop room as a pedestal purchase.
    result.rooms[shopIdx].pickups.add(
      centerPickup(game, dpkMap, cost = 25 + floorNumber * 10, offsetX = -110))

  # One elite combat room at depth >= 2.
  var eliteIdx = -1
  bestScore = -1
  for i, room in result.rooms:
    if room.kind != drkCombat or room.bfsDepth < 2: continue
    if room.bfsDepth > bestScore:
      bestScore = room.bfsDepth
      eliteIdx = i
  if eliteIdx >= 0:
    result.rooms[eliteIdx].kind = drkElite

  # Pre-roll encounters, obstacles, and the free compass pedestal.
  var compassCandidates: seq[int] = @[]
  for i, room in result.rooms:
    room.encounterSeed = rng.rand(1_000_000_000)
    room.obstacleSeed = rng.rand(1_000_000_000)
    case room.kind
    of drkCombat, drkElite:
      room.encounterBudget = 5 + floorNumber * 2 + room.bfsDepth + heatRank
      if room.kind == drkCombat:
        compassCandidates.add(i)
    of drkStart, drkShop, drkTreasure:
      room.cleared = true
      room.encounterBudget = 0
    of drkBoss:
      room.encounterBudget = 0
  if compassCandidates.len > 0:
    let pick = compassCandidates[rng.rand(compassCandidates.len - 1)]
    result.rooms[pick].pickups.add(centerPickup(game, dpkCompass, offsetY = -90))

  result.rooms[result.startIdx].visited = true
  result.rooms[result.startIdx].seen = true
  for dir in result.rooms[result.startIdx].doors:
    let n = result.neighborIndex(result.startIdx, dir)
    if n >= 0:
      result.rooms[n].seen = true

# ---------------------------------------------------------------------------
# Theme selection between floors

const FinalFloorTheme* = dftCorruptedSector
  ## The single arena that headlines the final floor (boss 12). The corrupted
  ## sector is the most degraded theme, fitting the run's last process.

proc isFinalDungeonFloor*(run: RogueliteRun): bool =
  ## The final floor offers one special "final boss" arena (always boss 12)
  ## instead of a three-theme roll. Gates generation, rendering and input.
  not run.isNil and run.floorNumber >= RogueliteFloorsToWin

proc generateThemeChoices*(run: RogueliteRun, unlockedBossTier: int = 1) =
  if run.isNil: return
  if isFinalDungeonFloor(run):
    # Final floor: no roll. A single fixed arena that always headlines boss 12.
    # Every slot resolves to it so any selection index lands on the same theme,
    # and the floor-select UI renders one special card.
    for i in 0 .. 2:
      run.nextThemeChoices[i] = FinalFloorTheme
    return
  var pool: seq[DungeonFloorTheme] = @[]
  for theme in DungeonFloorTheme:
    if theme notin run.usedThemes:
      pool.add(theme)
  if pool.len < 3:
    # Endless loops re-open the full pool.
    pool = @[]
    for theme in DungeonFloorTheme:
      pool.add(theme)

  # Offer 3 themes whose floor bosses are all DISTINCT (no duplicate boss on the
  # cards). Group the pool by the boss each theme maps to on this floor, then
  # draw one theme from 3 distinct boss-groups. When the floor's band has fewer
  # than 3 distinct bosses (the final floor is boss 12 only), the remaining slots
  # fall back to leftover themes - still distinct themes, even if the boss repeats.
  var groups = initTable[int, seq[DungeonFloorTheme]]()
  var bossOrder: seq[int] = @[]
  for theme in pool:
    let boss = dungeonBossNumberFor(theme, run.floorNumber, run.endlessLoop,
                                    unlockedBossTier)
    if boss notin groups:
      groups[boss] = @[]
      bossOrder.add(boss)
    groups[boss].add(theme)

  shuffle(bossOrder)
  var chosen: seq[DungeonFloorTheme] = @[]
  for boss in bossOrder:
    if chosen.len >= 3: break
    let pick = rand(groups[boss].len - 1)
    chosen.add(groups[boss][pick])
    groups[boss].delete(pick)

  if chosen.len < 3:
    var leftovers: seq[DungeonFloorTheme] = @[]
    for boss in bossOrder:
      for theme in groups[boss]:
        leftovers.add(theme)
    shuffle(leftovers)
    var idx = 0
    while chosen.len < 3 and idx < leftovers.len:
      chosen.add(leftovers[idx])
      inc idx

  for i in 0 .. 2:
    run.nextThemeChoices[i] = chosen[i]

# ---------------------------------------------------------------------------
# Room state changes

proc wipeRoomEntities*(game: Game) =
  ## Rooms do not persist live entities; clear everything transient.
  game.enemies = @[]
  game.bullets = @[]
  game.coins = @[]
  game.consumables = @[]
  game.attackWarnings = @[]
  game.lasers = @[]
  game.meteorites = @[]
  game.lightningBolts = @[]
  game.shockwaveRings = @[]
  game.walls = @[]
  game.pendingWallRespawns = @[]
  game.pendingBoss = nil
  game.pendingBossTimer = 0
  game.bossSpawnTimer = 0

proc spawnRoomObstacles(game: Game, room: DungeonRoom) =
  ## A few permanent circular obstacles, kept away from doors and the center.
  let def = themeDef(game.rogueliteRun.floor.theme)
  var rng = initRand(room.obstacleSeed)
  let count = def.obstacleMin + rng.rand(max(0, def.obstacleMax - def.obstacleMin))
  let w = game.screenWidth.float32
  let h = game.screenHeight.float32
  var attempts = 0
  var placed = 0
  while placed < count and attempts < 60:
    inc attempts
    let x = 130'f32 + rng.rand(1.0).float32 * (w - 260'f32)
    let y = 120'f32 + rng.rand(1.0).float32 * (h - 240'f32)
    let pos = newVector2f(x, y)
    # Keep the center lane and door lanes free
    if abs(x - w / 2) < 120 and abs(y - h / 2) < 120: continue
    if abs(x - w / 2) < 110 and (y < 170 or y > h - 170): continue
    if abs(y - h / 2) < 110 and (x < 170 or x > w - 170): continue
    var tooClose = false
    for wall in game.walls:
      if distance(pos, wall.pos) < 90:
        tooClose = true
        break
    for pickup in room.pickups:
      if distance(pos, pickup.pos) < 90:
        tooClose = true
        break
    if tooClose: continue
    # Boss-room obstacles re-form after the boss smashes them; combat-room ones
    # are gone for good once enemies break through. HP grows with floor depth
    # (and endless loops) so late-floor walls don't shatter instantly against
    # the bigger, faster crowds down there.
    let isBossRoom = room.kind == drkBoss
    let run = game.rogueliteRun
    let depth = (run.floorNumber - 1 + run.endlessLoop).float32
    let obstacleHp =
      if isBossRoom: BossObstacleHp + depth * BossObstacleHpPerFloor
      else: CombatObstacleHp + depth * CombatObstacleHpPerFloor
    game.walls.add(Wall(
      pos: pos,
      radius: 26 + rng.rand(1.0).float32 * 10,
      hp: obstacleHp, maxHp: obstacleHp,
      duration: 1.0,
      permanent: true,
      respawns: isBossRoom,
      obstacleTint: def.accent
    ))
    inc placed

proc applyRoomScaling(game: Game) =
  ## Mirrors the per-wave player scaling from startWave (game.nim): without
  ## this the player never grows while room threat keeps rising. Runs once per
  ## uncleared combat/elite/boss room, and also refreshes per-wave abilities.
  let waveScaling: float32 = 1.012
  game.player.maxHp *= waveScaling
  game.player.baselineMaxHp *= waveScaling  # Free growth, excluded from Juggernaut
  game.player.hp = min(game.player.hp * waveScaling, game.player.maxHp)
  game.player.damage *= waveScaling
  game.player.speed *= waveScaling
  game.player.baseSpeed *= waveScaling
  game.player.bulletSpeed = multiplyBulletSpeedDiminished(game.player.bulletSpeed, waveScaling)
  game.player.fireRate /= waveScaling

  game.player.timeWarpUsesThisWave = 0
  game.player.timeWarpCooldown = 0
  game.player.phaseShiftCooldown = 0
  game.player.bloodPactCooldown = 0
  game.player.conduitCooldown = 0
  game.player.aftershockCooldown = 0
  game.player.novaCooldown = 0
  if hasPowerUp(game.player, puCelestialVeil):
    game.player.celestialVeilCharges = 2

proc openDungeonDoors*(game: Game) =
  let room = currentDungeonRoom(game.rogueliteRun)
  if room.isNil: return
  room.cleared = true
  let floor = game.rogueliteRun.floor
  for dir in room.doors:
    let n = floor.neighborIndex(floor.currentRoom, dir)
    if n >= 0:
      floor.rooms[n].seen = true

proc enterRoom*(game: Game, roomIdx: int, enteredThrough: DoorDir) =
  ## Swap the live arena to the given room. Called mid-transition.
  let run = game.rogueliteRun
  let floor = run.floor
  floor.currentRoom = roomIdx
  let room = floor.rooms[roomIdx]
  room.visited = true
  room.seen = true

  wipeRoomEntities(game)
  game.player.pos = doorSpawnPos(game, enteredThrough)
  game.player.vel = newVector2f(0, 0)

  if room.kind in {drkCombat, drkElite, drkBoss}:
    spawnRoomObstacles(game, room)

  if room.cleared:
    game.waveInProgress = false
    game.waveEnemiesRemaining = 0
    game.waveEnemiesTotal = 0
    openDungeonDoors(game)
  else:
    case room.kind
    of drkBoss:
      # Boss rooms arm the boss-spawn machinery instead of a normal encounter.
      applyRoomScaling(game)
      game.waveInProgress = true
      game.waveEnemiesTotal = 0
      game.waveEnemiesRemaining = 0
      game.wavesUntilBoss = 0
      game.spawnTimer = 0
    of drkCombat, drkElite:
      applyRoomScaling(game)
      game.waveInProgress = true
      game.waveEnemiesTotal = room.encounterBudget
      game.waveEnemiesRemaining = room.encounterBudget
      game.wavesUntilBoss = 999
      game.spawnTimer = 0
      game.waveStartTime = game.time
    else:
      game.waveInProgress = false
      room.cleared = true
      openDungeonDoors(game)

proc startDungeonFloor*(game: Game, theme: DungeonFloorTheme) =
  ## Build the floor for the chosen theme and place the player in the start room.
  let run = game.rogueliteRun
  run.usedThemes.incl(theme)
  run.pendingFloorSelect = false
  game.bossPortalActive = false
  game.bossPortalTimer = 0
  run.floor = generateFloor(game, theme, run.floorNumber)
  run.floor.currentRoom = run.floor.startIdx
  wipeRoomEntities(game)
  game.player.pos = newVector2f(game.screenWidth.float32 / 2,
                                game.screenHeight.float32 / 2)
  game.player.vel = newVector2f(0, 0)
  game.waveInProgress = false
  game.waveEnemiesRemaining = 0
  game.waveEnemiesTotal = 0
  game.wavesUntilBoss = 999
  game.spawnTimer = 0
  game.roomTransitionActive = false
  game.roomTransitionTimer = 0
  openDungeonDoors(game)

proc selectFloorTheme*(game: Game, choiceIndex: int) =
  if game.rogueliteRun.isNil: return
  let idx = clamp(choiceIndex, 0, 2)
  startDungeonFloor(game, game.rogueliteRun.nextThemeChoices[idx])

proc onRoomCleared*(game: Game): DungeonClearOutcome =
  ## Combat/elite room finished: bank coins, award shards/keys, open doors.
  result = dcoNone
  let run = game.rogueliteRun
  let room = currentDungeonRoom(run)
  if room.isNil or room.cleared: return

  collectAllCoins(game)
  openDungeonDoors(game)
  game.waveInProgress = false
  run.totalRoomsCleared += 1
  playSound(stWaveComplete)

  let def = themeDef(run.floor.theme)
  let heatRank = heatChallengeRank(run.heat)
  let relicShardMultiplier = if run.hasRelic(rrtShardMagnet): 1.25'f32 else: 1.0'f32
  let effectiveShardMultiplier = def.shardMod * relicShardMultiplier
  let baseShard = 3 + run.floorNumber + heatRank * 2 + run.endlessLoop * 2
  var shardBonus = int(ceil(baseShard.float32 * effectiveShardMultiplier))

  var keyDropped = false
  if room.kind == drkElite:
    keyDropped = true
    shardBonus += int(ceil((6 + run.floorNumber * 2).float32 * effectiveShardMultiplier))
    game.player.coins += 12 + run.floorNumber * 5 + heatRank * 4
    if run.hasRelic(rrtEliteDividend):
      game.player.coins += 30
      shardBonus += int(ceil(16.0 * effectiveShardMultiplier))
    if heatRank > 0:
      run.coresEarned += heatRank + run.endlessLoop
      game.currencyIndicators.add(newCurrencyIndicator(
        game.player.pos.x + 22, game.player.pos.y - 20,
        heatRank + run.endlessLoop, cikCores))
  elif rand(100) < 25:
    keyDropped = true

  if keyDropped:
    run.keys += 1

  run.shardsEarned += max(1, shardBonus)
  game.currencyIndicators.add(newCurrencyIndicator(
    game.player.pos.x, game.player.pos.y - 36, max(1, shardBonus), cikDataShards))

  if room.kind in {drkCombat, drkElite}:
    # Power-ups now come exclusively from leveling up (see applyRoomClearLevelUps
    # in game.nim); room clears no longer trigger a draft. The counter is kept
    # harmless for any other consumers but no longer opens the draft.
    run.combatRoomsSinceDraft += 1
    if run.combatRoomsSinceDraft >= 2:
      run.combatRoomsSinceDraft = 0

proc markBossRoomCleared*(game: Game) =
  ## Called from the boss-defeated handler in game.nim.
  let run = game.rogueliteRun
  if run.isNil or run.floor.isNil: return
  run.floor.rooms[run.floor.bossIdx].cleared = true
  run.totalRoomsCleared += 1
  collectAllCoins(game)
  openDungeonDoors(game)
  game.waveInProgress = false

proc exitPortalPos*(game: Game): Vector2f =
  ## The boss-clear portal always forms at the center of the boss room.
  newVector2f(game.screenWidth.float32 / 2, game.screenHeight.float32 / 2)

proc spawnRogueliteExitPortal*(game: Game) =
  ## Open the swirling exit portal in the cleared boss room. The floor only
  ## advances once the player physically steps into it (see updateDungeon),
  ## instead of teleporting straight to the next floor select.
  game.bossPortalActive = true
  game.bossPortalTimer = 0
  playSound(stBossSpawn, 0.7)

# ---------------------------------------------------------------------------
# Per-frame update: transitions, doors, pickups, shop terminal

proc tryEnterDoor(game: Game, dir: DoorDir): bool =
  let run = game.rogueliteRun
  let floor = run.floor
  let n = floor.neighborIndex(floor.currentRoom, dir)
  if n < 0: return false
  let target = floor.rooms[n]
  if target.locked:
    if run.keys <= 0:
      return false
    run.keys -= 1
    target.locked = false
    playSound(stMenuSelect)
  game.roomTransitionActive = true
  game.roomTransitionTimer = 0
  game.roomTransitionDir = dir
  true

proc applyPickup(game: Game, room: DungeonRoom, pickup: DungeonPickup) =
  let run = game.rogueliteRun
  case pickup.kind
  of dpkKey:
    run.keys += 1
    playSound(stCoinPickup, 0.7)
  of dpkCompass:
    run.floor.compassFound = true
    playSound(stPowerUp, 0.6)
  of dpkMap:
    run.floor.mapRevealed = true
    playSound(stPowerUp, 0.6)
  of dpkRelicPedestal:
    if grantNextUnlockedRelic(game):
      playSound(stPowerUp, 0.8)
    else:
      let bonus = 18 + run.floorNumber * 4
      run.shardsEarned += bonus
      game.currencyIndicators.add(newCurrencyIndicator(
        pickup.pos.x, pickup.pos.y - 20, bonus, cikDataShards))
      playSound(stCoinPickup, 0.7)
  of dpkShardCache:
    let heatRank = heatChallengeRank(run.heat)
    let bonus = 14 + run.floorNumber * 4 + heatRank * 5 + run.endlessLoop * 8
    run.shardsEarned += bonus
    game.currencyIndicators.add(newCurrencyIndicator(
      pickup.pos.x, pickup.pos.y - 20, bonus, cikDataShards))
    playSound(stCoinPickup, 0.7)
  pickup.taken = true

proc shopTerminalPos*(game: Game): Vector2f =
  newVector2f(game.screenWidth.float32 / 2, game.screenHeight.float32 / 2)

proc playerOnShopTerminal*(game: Game): bool =
  let room = currentDungeonRoom(game.rogueliteRun)
  if room.isNil or room.kind != drkShop: return false
  distance(game.player.pos, shopTerminalPos(game)) < ShopTerminalRadius

proc updateDungeon*(game: Game, dt: float32): bool =
  ## Returns true while a room transition is active (gameplay should pause).
  let run = game.rogueliteRun
  if run.isNil or run.floor.isNil: return false
  let floor = run.floor

  if game.roomTransitionActive:
    let prev = game.roomTransitionTimer
    game.roomTransitionTimer += dt
    let half = RoomTransitionDuration / 2
    if prev < half and game.roomTransitionTimer >= half:
      # Midpoint: swap rooms while the screen is dark.
      let n = floor.neighborIndex(floor.currentRoom, game.roomTransitionDir)
      if n >= 0:
        enterRoom(game, n, opposite(game.roomTransitionDir))
    if game.roomTransitionTimer >= RoomTransitionDuration:
      game.roomTransitionActive = false
      game.roomTransitionTimer = 0
    return true

  let room = floor.rooms[floor.currentRoom]

  # Boss-clear exit portal: the floor only advances once the player walks into
  # the portal. It animates in first (spawn animation) before becoming enterable.
  if game.bossPortalActive and floor.currentRoom == floor.bossIdx:
    game.bossPortalTimer += dt
    if game.bossPortalTimer >= ExitPortalSpawnDuration and
       distance(game.player.pos, exitPortalPos(game)) < ExitPortalRadius + game.player.radius:
      game.bossPortalActive = false
      playSound(stTeleport)
      generateThemeChoices(run, unlockedBossTierOf(game))
      game.selectedRogueliteTheme = 0
      game.state = gsRogueliteFloorSelect
      return true

  # Pedestal pickups (only in safe/cleared state for combat rooms)
  for pickup in room.pickups:
    if pickup.taken: continue
    if distance(game.player.pos, pickup.pos) < PickupRadius + game.player.radius:
      if pickup.costCredits > 0:
        if game.player.coins >= pickup.costCredits and
           (isKeyPressed(globalSettings.keybinds[kaPlaceWall]) or isKeyPressed(Enter) or isGamepadBindPressed(globalSettings.gamepadBinds, kaPlaceWall)):
          game.player.coins -= pickup.costCredits
          applyPickup(game, room, pickup)
      else:
        applyPickup(game, room, pickup)

  # Shop terminal opens the existing shop UI. Returning true skips the rest
  # of this frame's gameplay update so the E press can't double as the
  # wall-placement toggle.
  if room.kind == drkShop and playerOnShopTerminal(game) and
     (isKeyPressed(globalSettings.keybinds[kaPlaceWall]) or isKeyPressed(Enter) or isGamepadBindPressed(globalSettings.gamepadBinds, kaPlaceWall)):
    game.state = gsShop
    game.shopSidebarScroll = 0
    playSound(stMenuSelect)
    return true

  # Door traversal (only when the room is cleared)
  if room.cleared and not game.roomTransitionActive:
    let playerRect = Rectangle(
      x: game.player.pos.x - game.player.radius,
      y: game.player.pos.y - game.player.radius,
      width: game.player.radius * 2,
      height: game.player.radius * 2)
    for dir in room.doors:
      if checkCollisionRecs(playerRect, doorRect(game, dir)):
        if tryEnterDoor(game, dir):
          break
  false

# ---------------------------------------------------------------------------
# Drawing: doors, pedestals, transition fade

proc doorColor(game: Game, room: DungeonRoom, dir: DoorDir): Color =
  let run = game.rogueliteRun
  let n = run.floor.neighborIndex(run.floor.currentRoom, dir)
  let accent = themeAccent(run.floor.theme)
  if not room.cleared:
    return Color(r: 200, g: 60, b: 60, a: 220)
  if n >= 0 and run.floor.rooms[n].locked:
    return Color(r: 255, g: 200, b: 60, a: 230)
  withAlpha(accent, 230)

proc drawPickupPedestal(game: Game, pickup: DungeonPickup) =
  let cx = pickup.pos.x.int32
  let cy = pickup.pos.y.int32
  let pulse = 1.0'f32 + sin(game.time * 3.0'f32) * 0.12'f32
  drawCircle(Vector2(x: pickup.pos.x, y: pickup.pos.y + 12), 18, Color(r: 25, g: 32, b: 44, a: 220))
  drawCircleLines(cx, cy + 12, 18'f32, Color(r: 90, g: 110, b: 140, a: 255))
  case pickup.kind
  of dpkKey:
    drawCircleLines(cx, cy - 6, 7'f32 * pulse, Gold)
    drawCircleLines(cx, cy - 6, 3'f32, Color(r: 255, g: 215, b: 0, a: 150))  # bow hole
    drawRectangle(cx - 1, cy - 2, 3, 13, Gold)                                # shaft
    drawRectangle(cx + 1, cy + 6, 5, 3, Gold)                                 # lower tooth
    drawRectangle(cx + 1, cy + 2, 4, 3, Color(r: 255, g: 215, b: 0, a: 220))  # upper tooth
  of dpkCompass:
    let fx = cx.float32
    let fy = (cy - 2).float32
    let ring = 11.0'f32 * pulse
    let rim = Color(r: 120, g: 220, b: 255, a: 255)
    # Bezel: dark dial face + bright outer rim + faint inner ring
    drawCircle(Vector2(x: fx, y: fy), ring, Color(r: 18, g: 40, b: 55, a: 200))
    drawCircleLines(cx, cy - 2, ring, rim)
    drawCircleLines(cx, cy - 2, ring - 3.0'f32, Color(r: 120, g: 220, b: 255, a: 110))
    # Cardinal tick marks (N/E/S/W)
    drawLine(Vector2(x: fx, y: fy - ring), Vector2(x: fx, y: fy - ring + 4.0'f32), 1.5'f32, rim)
    drawLine(Vector2(x: fx, y: fy + ring), Vector2(x: fx, y: fy + ring - 4.0'f32), 1.5'f32, rim)
    drawLine(Vector2(x: fx - ring, y: fy), Vector2(x: fx - ring + 4.0'f32, y: fy), 1.5'f32, rim)
    drawLine(Vector2(x: fx + ring, y: fy), Vector2(x: fx + ring - 4.0'f32, y: fy), 1.5'f32, rim)
    # Two-tone needle: red half points north, pale half points south
    let nLen = ring - 2.0'f32
    let hw = 3.5'f32
    let north = Vector2(x: fx, y: fy - nLen)
    let south = Vector2(x: fx, y: fy + nLen)
    let east = Vector2(x: fx + hw, y: fy)
    let west = Vector2(x: fx - hw, y: fy)
    drawTriangle(north, west, east, Color(r: 255, g: 90, b: 90, a: 255))
    drawTriangle(south, east, west, Color(r: 210, g: 235, b: 250, a: 255))
    drawTriangleLines(north, west, east, Color(r: 255, g: 150, b: 150, a: 220))
    drawTriangleLines(south, east, west, Color(r: 235, g: 245, b: 255, a: 220))
    drawCircle(Vector2(x: fx, y: fy), 1.8'f32, RayWhite)  # center hub
  of dpkMap:
    let green = Color(r: 150, g: 255, b: 170, a: 255)
    let fold = Color(r: 90, g: 170, b: 120, a: 200)
    let mxL = cx - 11
    let myT = cy - 13
    const mw = 22'i32
    const mh = 17'i32
    # Parchment sheet with creases (a folded treasure map)
    drawRectangle(mxL, myT, mw, mh, Color(r: 22, g: 40, b: 30, a: 200))
    drawRectangleLines(Rectangle(x: mxL.float32, y: myT.float32, width: mw.float32, height: mh.float32),
                       1.5'f32, green)
    drawLine(mxL + 7, myT, mxL + 7, myT + mh, fold)
    drawLine(mxL + 15, myT, mxL + 15, myT + mh, fold)
    # Dashed route wandering toward the marker
    drawLine(mxL + 3, myT + mh - 4, mxL + 7, myT + mh - 9, green)
    drawLine(mxL + 9, myT + mh - 10, mxL + 13, myT + 5, green)
    drawLine(mxL + 14, myT + 5, mxL + 17, myT + 7, green)
    # "X marks the spot" destination
    let xMx = mxL + 17
    let xMy = myT + 7
    drawLine(xMx - 2, xMy - 2, xMx + 2, xMy + 2, Color(r: 255, g: 90, b: 90, a: 255))
    drawLine(xMx - 2, xMy + 2, xMx + 2, xMy - 2, Color(r: 255, g: 90, b: 90, a: 255))
    if pickup.costCredits > 0:
      let label = "$" & $pickup.costCredits & " [E]"
      let lw = measureText(label, 12)
      drawText(label, cx - lw div 2, cy + 22, 12,
               if game.player.coins >= pickup.costCredits: Gold
               else: Color(r: 255, g: 90, b: 90, a: 255))
  of dpkRelicPedestal:
    drawPoly(Vector2(x: pickup.pos.x, y: pickup.pos.y - 6), 6, 9'f32 * pulse, 0,
             Color(r: 190, g: 140, b: 255, a: 255))
  of dpkShardCache:
    drawPoly(Vector2(x: pickup.pos.x, y: pickup.pos.y - 5), 3, 9'f32 * pulse, 180,
             Color(r: 70, g: 215, b: 255, a: 255))

proc drawExitPortal(game: Game) =
  ## The swirling boss-clear portal: a dark vortex with rotating accent spiral
  ## arms that scale into existence (spawn animation) then idle-pulse.
  let run = game.rogueliteRun
  let accent = themeAccent(run.floor.theme)
  let center = exitPortalPos(game)
  let cx = center.x
  let cy = center.y
  let tm = game.time
  let spawnT = clamp(game.bossPortalTimer / ExitPortalSpawnDuration, 0.0'f32, 1.0'f32)
  # Ease-out scale-in so the portal snaps open then settles.
  let scale = 1.0'f32 - pow(1.0'f32 - spawnT, 3.0'f32)
  let baseR = ExitPortalRadius * scale
  const tau = 6.2831853'f32

  # Outer glow + dark core
  drawCircle(Vector2(x: cx, y: cy), baseR * 1.4'f32,
             withAlpha(accent, uint8(40.0'f32 * scale)))
  drawCircle(Vector2(x: cx, y: cy), baseR,
             Color(r: 8, g: 6, b: 18, a: uint8(235.0'f32 * scale)))

  # Swirling spiral arms made of fading dots
  const arms = 3
  const pointsPerArm = 26
  for a in 0..<arms:
    let armOffset = (a.float32 / arms.float32) * tau
    for i in 0..<pointsPerArm:
      let frac = i.float32 / pointsPerArm.float32
      let ang = armOffset + frac * 5.0'f32 + tm * 2.2'f32
      let rr = baseR * (0.12'f32 + frac * 0.85'f32)
      let px = cx + cos(ang) * rr
      let py = cy + sin(ang) * rr
      let aa = uint8(255.0'f32 * (1.0'f32 - frac) * scale)
      drawCircle(Vector2(x: px, y: py), 1.5'f32 + (1.0'f32 - frac) * 2.5'f32,
                 withAlpha(accent, aa))

  # Rotating rim rings
  for k in 0..2:
    let rr = baseR * (0.6'f32 + k.float32 * 0.18'f32)
    let pulse = 0.6'f32 + 0.4'f32 * sin(tm * 3.0'f32 - k.float32)
    drawCircleLines(cx.int32, cy.int32, rr,
                    Color(r: accent.r, g: accent.g, b: accent.b,
                          a: uint8(200.0'f32 * pulse * scale)))

  # Spawn shockwave expanding outward while opening
  if spawnT < 1.0'f32:
    let shockR = ExitPortalRadius * (0.5'f32 + spawnT * 1.8'f32)
    drawCircleLines(cx.int32, cy.int32, shockR,
                    Color(r: accent.r, g: accent.g, b: accent.b,
                          a: uint8(180.0'f32 * (1.0'f32 - spawnT))))
  else:
    # Prompt only once the portal is fully open and enterable.
    let label = t("dungeon_portal_prompt")
    let lw = measureText(label, 16)
    let bob = sin(tm * 3.0'f32) * 3.0'f32
    drawText(label, cx.int32 - lw div 2, (cy - baseR - 30 + bob).int32, 16, RayWhite)

proc drawDungeonOverlay*(game: Game) =
  ## Doors, pedestals, shop terminal, and the room-transition fade.
  ## Called from drawGame for roguelite mode (after entities, before HUD).
  let run = game.rogueliteRun
  if run.isNil or run.floor.isNil: return
  let floor = run.floor
  let room = floor.rooms[floor.currentRoom]
  let accent = themeAccent(floor.theme)

  # Doors
  for dir in room.doors:
    let rect = doorRect(game, dir)
    let color = doorColor(game, room, dir)
    let fill = withAlpha(color, 60)
    drawRectangle(rect, fill)
    drawRectangleLines(rect, 2.0'f32, color)
    let n = floor.neighborIndex(floor.currentRoom, dir)
    if room.cleared and n >= 0 and floor.rooms[n].locked:
      let label = if run.keys > 0: t("dungeon_door_unlock") else: t("dungeon_door_locked")
      let lw = measureText(label, 14)
      var lx = (rect.x + rect.width / 2).int32 - lw div 2
      var ly = (rect.y + rect.height / 2).int32 - 7
      case dir
      of ddUp: ly = (rect.y + rect.height + 8).int32
      of ddDown: ly = (rect.y - 22).int32
      of ddLeft: lx = (rect.x + rect.width + 8).int32
      of ddRight: lx = (rect.x - lw.float32 - 8).int32
      drawText(label, lx, ly, 14, Color(r: 255, g: 200, b: 60, a: 255))

  # Pedestals
  for pickup in room.pickups:
    if not pickup.taken:
      drawPickupPedestal(game, pickup)

  # Shop terminal
  if room.kind == drkShop:
    let pos = shopTerminalPos(game)
    let pulse = 1.0'f32 + sin(game.time * 2.5'f32) * 0.08'f32
    drawRectangle((pos.x - 26).int32, (pos.y - 20).int32, 52, 40, Color(r: 22, g: 30, b: 42, a: 235))
    drawRectangleLines(Rectangle(x: pos.x - 26, y: pos.y - 20, width: 52, height: 40),
                       2.0'f32, accent)
    drawText("$", (pos.x - 5).int32, (pos.y - 12).int32, 24, Gold)
    if playerOnShopTerminal(game):
      let label = t("dungeon_shop_prompt")
      let lw = measureText(label, 14)
      drawText(label, pos.x.int32 - lw div 2, (pos.y - 44 * pulse).int32, 14, RayWhite)

  # Boss-clear exit portal (drawn under the transition fade)
  if game.bossPortalActive and floor.currentRoom == floor.bossIdx:
    drawExitPortal(game)

  # Transition fade (dark at the midpoint)
  if game.roomTransitionActive:
    let half = RoomTransitionDuration / 2
    let p = game.roomTransitionTimer
    let alphaF = if p < half: p / half else: 1.0'f32 - (p - half) / half
    drawRectangle(0, 0, game.screenWidth, game.screenHeight,
                  Color(r: 0, g: 0, b: 0, a: uint8(clamp(alphaF, 0.0, 1.0) * 255)))
