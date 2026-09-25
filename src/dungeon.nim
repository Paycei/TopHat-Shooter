## Sector core for the roguelite mode ("Deep Recovery").
##
## A run descends 4 themed SECTORS drawn from a 7-theme pool. A sector is a
## forward path through folders: a start room, a few reward folders, then the
## sector's SERVICE (the boss). Clearing a folder materializes its reward in
## the middle of the room; once it is claimed, 2-3 exits open on the left, top
## and right walls, each labelled with the folder it leads to and what that
## folder pays (/bin power-up, /updates patch, /cache credits, /restore repair,
## /shards Data Shards, /pkg package stalls, /quarantine elite). Picking a
## door IS the build decision (the Hades model); there is no going back.
##
## Every layer's exits are rolled when the sector is generated, deterministic
## from the run seed, so a save only needs the theme, the path of exits taken
## and the live room's state (run_save.nim).
##
## This module owns sector generation, themes, encounter pacing (pulses),
## rewards, stalls and room transitions. It must NOT import game.nim (game.nim
## imports this module) nor game/death (death -> run_save -> dungeon). Enemy
## spawning itself stays in game.nim; installing a bought power-up and saving
## are handed back through the DungeonFrame that updateDungeon returns.

import raylib, random, math, tables, strutils
import gamepad_input, particle_types, types, roguelite, powerup, powerup_data, patches, player,
       particle_pool, sound, localization, boss_definitions, settings, coin, xp_orb, utils,
       game/combat, ui/icon_drawing, ui/ui_helpers, ui/proximity_card

const
  DoorZoneWidth* = 120'f32   # Length of the door opening along the edge
  DoorZoneDepth* = 34'f32    # How far the door zone reaches into the room
  PickupRadius* = 26'f32
  InteractRadius* = 62'f32   # [E] range for pedestals and stalls
  PickupSpawnTime* = 0.7'f32 # Materialize animation; claimable afterwards
  PickupMagnetDelay = 1.2'f32
  PickupMagnetSpeed = 330'f32
  ExitPortalRadius* = 48'f32           # Player-entry radius of the boss-clear portal
  ExitPortalSpawnDuration* = 1.1'f32   # Spawn animation length before it becomes enterable
  RoomTransitionDuration* = 0.35'f32
  CombatObstacleHp* = 4'f32          # Sector-1 combat obstacle HP; a kiting crowd chips these down
  BossObstacleHp* = 6'f32            # Sector-1 boss obstacle HP; adds chip them, the boss one-shots
  CombatObstacleHpPerFloor* = 2'f32  # Added per sector (and per endless loop) so late walls hold up
  BossObstacleHpPerFloor* = 3'f32    # Added per sector (and per endless loop)
  BossWallRespawnDelay* = 8'f32      # Seconds a smashed boss-room obstacle stays gone

  # Sector shape: reward layers per sector (endless loops use the last).
  SectorLayers = [5, 5, 6, 6]
  ThreeExitChance = [35, 50, 55, 60]   # % chance a layer past the first offers 3 doors

  # Encounters sit on the wave-mode swarm curve (calculateWaveEnemyCount at the
  # room's wave-equivalent) and arrive in pulses, so a folder is a fight with
  # an arc instead of one burst that lands in 1.5 s.
  RoomEnemyCountScale = 0.8'f32
  QuarantineCountScale = 0.7'f32       # fewer bodies, far more elites
  FirstSectorCountScale = 0.875'f32    # sector 1 onboarding: 0.8 -> 0.7 of the curve
  PulseEnemies = 18                    # roughly one pulse per this many enemies
  PulseFirstDelay = 0.8'f32
  PulseMaxGap = 9.0'f32                # next pulse no later than this after the last one lands
  PulseAliveFraction = 0.35'f32        # ...or as soon as the last pulse is mostly cleared

  # Room rewards.
  RepairRewardPercent = 35
  RoomScalingPerRoom = 1.016'f32       # free player growth per uncleared room entered
  RogueliteServiceHpScale = 0.75'f32   # SERVICE (boss) HP pool trim, see tuneDungeonBossStats

type
  DungeonThemeDef* = object
    accent*: Color
    ## Roster entries unlock progressively: an enemy only spawns once the
    ## room's effective threat reaches its minThreat. The folders field the
    ## roguelite's own legacy processes (etFragment..etCorruptor), written for
    ## room play: cover, walls and obstacles are part of every behaviour.
    roster*: seq[tuple[enemy: EnemyType, weight: int, minThreat: int]]
    bossNumber*: int          # The folder's guardian (boss definition ID)
    pressureMod*: float32     # Scales encounter difficulty
    eliteBonus*: int          # Added to the elite-chance roll input
    shardMod*: float32        # Scales shard rewards
    obstacleMin*, obstacleMax*: int

  DungeonFrame* = object
    ## What a frame of dungeon logic needs game.nim to do on its behalf.
    pauseSim*: bool      # transition or modal opened: skip the rest of this frame's gameplay
    install*: PowerUp    # level > 0: a bought package, routed through installPowerUp
    checkpoint*: bool    # progress worth saving (door taken, reward claimed, purchase)

var focusedPickup = -1
  ## Index (into the live room's pickups) of the pedestal/stall in [E] range,
  ## or -1. Written by updateDungeon, read by drawDungeonOverlay for the card.

# ---------------------------------------------------------------------------
# Themes

const FinalFloorTheme* = dftCorruptedSector
  ## The single arena that headlines the final sector (the Omega Entity). The
  ## corrupted sector is the most degraded theme, fitting the run's last
  ## process, and is reserved for it: it is never offered on sectors 1-3.

proc themeDef*(theme: DungeonFloorTheme): DungeonThemeDef =
  # Threat reference (heat 1): sector 1 rooms sit around threat 1-5,
  # sector 2 ~6-11, sector 3 ~11-17, sector 4 ~16-22.
  # Gates are intentionally light: complex types are welcome early because
  # tuneDungeonEnemyStats compresses their stats toward the room's threat.
  case theme
  of dftFirewall:
    DungeonThemeDef(
      accent: Color(r: 255, g: 110, b: 48, a: 255),
      # Shield walls and turrets dug in behind the obstacles, drivers ramming through.
      roster: @[(etFragment, 30, 0), (etPortGuard, 30, 0), (etSentry, 25, 2),
                (etDriver, 15, 4)],
      bossNumber: 17, pressureMod: 1.0, eliteBonus: 0, shardMod: 1.0,
      obstacleMin: 2, obstacleMax: 4)
  of dftRecycleBin:
    DungeonThemeDef(
      accent: Color(r: 150, g: 190, b: 140, a: 255),
      # Deleted files that won't stay deleted: mimics among the scraps,
      # restorers raising the fallen.
      roster: @[(etFragment, 40, 0), (etMimic, 30, 0), (etRestorer, 30, 2)],
      bossNumber: 18, pressureMod: 0.95, eliteBonus: 0, shardMod: 1.0,
      obstacleMin: 3, obstacleMax: 5)
  of dftRegistry:
    DungeonThemeDef(
      accent: Color(r: 90, g: 160, b: 255, a: 255),
      # Guarded keys: shields up front, restorers behind, the floor rotting.
      roster: @[(etFragment, 25, 0), (etPortGuard, 25, 0), (etRestorer, 25, 2),
                (etCorruptor, 25, 4)],
      bossNumber: 19, pressureMod: 1.05, eliteBonus: 2, shardMod: 1.1,
      obstacleMin: 3, obstacleMax: 5)
  of dftNetwork:
    DungeonThemeDef(
      accent: Color(r: 0, g: 220, b: 255, a: 255),
      # Traffic: packets ricocheting off every obstacle, sentries on the hops.
      roster: @[(etFragment, 30, 0), (etPacket, 35, 0), (etSentry, 20, 2),
                (etMimic, 15, 4)],
      bossNumber: 20, pressureMod: 1.1, eliteBonus: 3, shardMod: 1.15,
      obstacleMin: 1, obstacleMax: 3)
  of dftKernel:
    DungeonThemeDef(
      accent: Color(r: 150, g: 95, b: 235, a: 255),
      # Heavy iron: drivers charging through rooted sentries' fire.
      roster: @[(etFragment, 25, 0), (etDriver, 30, 0), (etSentry, 25, 2),
                (etPortGuard, 20, 4)],
      bossNumber: 21, pressureMod: 1.18, eliteBonus: 4, shardMod: 1.25,
      obstacleMin: 2, obstacleMax: 4)
  of dftCache:
    DungeonThemeDef(
      accent: Color(r: 70, g: 215, b: 195, a: 255),
      # Stale memory: mimics, bouncing packets, corrupted tiles everywhere.
      roster: @[(etFragment, 25, 0), (etMimic, 30, 0), (etPacket, 25, 2),
                (etCorruptor, 20, 3)],
      bossNumber: 22, pressureMod: 1.12, eliteBonus: 3, shardMod: 1.2,
      obstacleMin: 2, obstacleMax: 4)
  of dftCorruptedSector:
    DungeonThemeDef(
      accent: Color(r: 255, g: 80, b: 200, a: 255),
      # The bottom of the stack: every legacy process at once.
      roster: @[(etFragment, 16, 0), (etPortGuard, 12, 0), (etMimic, 10, 0),
                (etPacket, 12, 0), (etSentry, 12, 2), (etRestorer, 10, 2),
                (etDriver, 14, 2), (etCorruptor, 14, 4)],
      bossNumber: 23, pressureMod: 1.3, eliteBonus: 8, shardMod: 1.45,
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

proc themeFolder*(theme: DungeonFloorTheme): string =
  ## Root directory of a sector in the HUD breadcrumb (C:\FIREWALL\...). A
  ## path, not prose, so it is deliberately not localized.
  case theme
  of dftFirewall: "FIREWALL"
  of dftRecycleBin: "RECYCLER"
  of dftRegistry: "REGISTRY"
  of dftNetwork: "NETWORK"
  of dftKernel: "KERNEL"
  of dftCache: "CACHE"
  of dftCorruptedSector: "BADSECTOR"

# ---------------------------------------------------------------------------
# Folder rewards

proc rewardFolderKey(reward: RoomReward): string =
  case reward
  of rrwNone: ""
  of rrwDraft: "bin"
  of rrwPatch: "updates"
  of rrwCredits: "cache"
  of rrwRepair: "restore"
  of rrwShards: "shards"
  of rrwShop: "pkg"
  of rrwQuarantine: "quarantine"

proc rewardFolderName*(reward: RoomReward): string =
  ## "/bin", "/pkg" ... (a path: not localized).
  "/" & rewardFolderKey(reward)

proc rewardLabel*(reward: RoomReward): string =
  ## What the folder pays, in words, for the door subtitle.
  if reward == rrwNone: "" else: t("room_reward_" & rewardFolderKey(reward))

proc rewardAccent*(reward: RoomReward): Color =
  case reward
  of rrwNone: Color(r: 150, g: 170, b: 200, a: 255)
  of rrwDraft: Color(r: 110, g: 220, b: 255, a: 255)
  of rrwPatch: Color(r: 120, g: 200, b: 255, a: 255)
  of rrwCredits: Color(r: 255, g: 215, b: 70, a: 255)
  of rrwRepair: Color(r: 110, g: 235, b: 160, a: 255)
  of rrwShards: Color(r: 90, g: 225, b: 255, a: 255)
  of rrwShop: Color(r: 255, g: 185, b: 90, a: 255)
  of rrwQuarantine: Color(r: 255, g: 90, b: 80, a: 255)

proc rewardRoomKind(reward: RoomReward): DungeonRoomKind =
  case reward
  of rrwShop: drkShop
  of rrwQuarantine: drkElite
  of rrwNone: drkStart
  of rrwDraft, rrwPatch, rrwCredits, rrwRepair, rrwShards: drkCombat

# ---------------------------------------------------------------------------
# Geometry

proc opposite*(dir: DoorDir): DoorDir =
  case dir
  of ddUp: ddDown
  of ddDown: ddUp
  of ddLeft: ddRight
  of ddRight: ddLeft

proc currentDungeonRoom*(run: RogueliteRun): DungeonRoom =
  if run.isNil or run.floor.isNil or run.floor.rooms.len == 0:
    return nil
  run.floor.rooms[clamp(run.floor.currentRoom, 0, run.floor.rooms.high)]

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

proc roomCenter(game: Game): Vector2f =
  newVector2f(game.screenWidth.float32 / 2, game.screenHeight.float32 / 2)

proc exitsOf*(floor: DungeonFloor, room: DungeonRoom): seq[DungeonExit] =
  ## The doors out of `room`: the exits of the next layer (none past SERVICE).
  if floor.isNil or room.isNil or room.layer + 1 >= floor.layers.len:
    return @[]
  floor.layers[room.layer + 1].exits

proc exitsOpen*(room: DungeonRoom): bool =
  ## A folder's exits open once it is cleared AND its reward is collected.
  not room.isNil and room.kind != drkBoss and room.cleared and room.rewardClaimed

proc sectorRewardLayers*(floor: DungeonFloor): int =
  ## Reward layers between the start room and SERVICE.
  if floor.isNil: 0 else: max(0, floor.layers.len - 2)

# ---------------------------------------------------------------------------
# Difficulty

proc dungeonEffectiveThreat*(run: RogueliteRun, room: DungeonRoom): int =
  let heatRank = heatChallengeRank(run.heat)
  (run.floorNumber - 1) * 5 + room.layer +
    heatRank * RogueliteHeatRosterWaveOffset + run.endlessLoop * 10

proc dungeonEnemyDifficulty*(run: RogueliteRun, room: DungeonRoom): float32 =
  let def = themeDef(run.floor.theme)
  let heatRank = heatChallengeRank(run.heat)
  dungeonEffectiveThreat(run, room).float32 / 4.0'f32 * def.pressureMod +
    heatRank.float32 * RogueliteHeatDifficultyPerTier +
    run.endlessLoop.float32 * 1.0'f32

proc dungeonRoomWaveEquivalent*(run: RogueliteRun, room: DungeonRoom): float32 =
  ## Maps room threat onto the wave-mode scale (sector 1 plays like waves 2-12,
  ## sector 4 like the wave-mode late game). Used to calibrate stat
  ## compression, elite stat magnitudes and swarm density against the
  ## wave-tuned numbers.
  max(1.0'f32, dungeonEffectiveThreat(run, room).float32 * 2.5'f32)

proc dungeonEliteRoll*(run: RogueliteRun, room: DungeonRoom): int =
  ## CHANCE input for makeElite only - the +30 quarantine boost guarantees
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
  # The survival horde never spawns in a folder.
  of etThread..etInterrupt: 1
  # The roguelite roster is written for sector 1 (wave-equivalent ~2-12):
  # only the tougher types compress, and only in the very first rooms.
  of etFragment: 1
  of etPortGuard, etSentry, etMimic: 4
  of etRestorer, etPacket, etCorruptor: 6
  of etDriver: 8
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

proc dungeonBossNumberFor*(theme: DungeonFloorTheme,
                           floorNumber, endlessLoop, heat: int): int =
  ## The SERVICE that will headline `floorNumber` for `theme`: every folder
  ## theme has its own legacy guardian, and the final sector always fields
  ## the Omega Entity's roguelite kit. Which sector a guardian appears in only
  ## changes its numbers (tuneDungeonBossStats), never which boss it is. Pure
  ## so the theme-select preview can call it before the sector exists.
  if floorNumber >= RogueliteFloorsToWin:
    23
  elif theme == FinalFloorTheme:
    # Only a save from before the final theme was reserved gets here (a
    # corrupted sector mid-run): field a guardian, picked deterministically so
    # a reload never swaps it.
    17 + (floorNumber + endlessLoop) mod 6  # guardians 17..22
  else:
    themeDef(theme).bossNumber

proc dungeonBossNumber*(game: Game): int =
  let run = game.rogueliteRun
  dungeonBossNumberFor(run.floor.theme, run.floorNumber, run.endlessLoop, run.heat)

proc dungeonBossWaveEquivalent(run: RogueliteRun): float32 =
  ## The wave-mode boss slot a SERVICE should feel like: sector 1 plays like
  ## the wave-5 boss fight, sector 4 like wave ~35, pushed up by heat/endless.
  let heatRank = heatChallengeRank(run.heat)
  5.0'f32 + (run.floorNumber - 1).float32 * 10.0'f32 +
    heatRank.float32 * 5.0'f32 + run.endlessLoop.float32 * 15.0'f32

const ServiceDamageRef = [1.0'f32, 4.5, 12.0, 14.5]
  ## Typical attack damage a SERVICE lands in sectors 1-4 (wave slots 5 / 15 /
  ## 25 / 35): the medians the campaign-boss SERVICEs fought at before the
  ## roguelite had its own roster, kept so the guardians inherit the tuned
  ## pressure of each sector rather than the wave curve's.

proc serviceDamageRef(slotWave: float32): float32 =
  let pos = max(0.0'f32, (slotWave - 5.0'f32) / 10.0'f32)
  let last = ServiceDamageRef.high
  if pos >= last.float32:
    return ServiceDamageRef[last] * pow(1.05'f32, (slotWave - 35.0'f32) / 5.0'f32)
  let lo = int(floor(pos))
  ServiceDamageRef[lo] + (ServiceDamageRef[lo + 1] - ServiceDamageRef[lo]) * (pos - lo.float32)

proc tuneDungeonBossStats*(boss: Enemy, run: RogueliteRun) =
  ## A guardian is authored at the sector-1 budget and may headline any
  ## sector (its folder theme can be picked anywhere), and the Omega kit is
  ## authored at the campaign finale. Normalize the spawned boss to the
  ## sector's slot on the boss curve, up or down: it keeps its mechanics,
  ## phases and weak points but fights with sector-appropriate HP and attack
  ## damage (damageTuning, applied in executeCustomBossAttack).
  ## RogueliteServiceHpScale trims the pool on top: a roguelite build has no
  ## between-wave stat shop behind it (measured: SERVICEs otherwise ran 2-6 min).
  if boss.isNil or not boss.isBoss or run.isNil:
    return
  let slot = dungeonBossWaveEquivalent(run)
  normalizeBossToSlot(boss, slot, RogueliteServiceHpScale)
  # Attack damage follows the sector's SERVICE reference instead of the wave
  # curve (see ServiceDamageRef).
  let authoredRef = bossSlotDamageRef(bossAuthoredSlotWave(boss.bossDefinitionID).float32)
  let f = serviceDamageRef(slot) / max(0.01'f32, authoredRef)
  if boss.damageTuning > 0:
    boss.contactDamage *= f / boss.damageTuning
    boss.rangedDamage *= f / boss.damageTuning
  boss.damageTuning = f

proc rollEncounterEnemyType*(run: RogueliteRun, room: DungeonRoom): EnemyType =
  ## Weighted pick from the sector theme's roster (non-deterministic on
  ## purpose: the budget is pre-rolled, the composition order is not). Entries
  ## above the room's threat are excluded so early rooms only see cheap types.
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
# Sector generation

proc sectorLayerCount(floorNumber, endlessLoop: int): int =
  if endlessLoop > 0: SectorLayers[^1]
  else: SectorLayers[clamp(floorNumber, 1, SectorLayers.len) - 1]

proc threeExitChance(floorNumber: int): int =
  ThreeExitChance[clamp(floorNumber, 1, ThreeExitChance.len) - 1]

proc rewardWeight(reward: RoomReward, floorNumber: int): int =
  let late = floorNumber >= 2
  case reward
  of rrwDraft: 30
  of rrwCredits: 18
  of rrwShards: 12
  of rrwRepair: (if late: 12 else: 8)
  of rrwPatch: 12
  of rrwQuarantine: (if late: 14 else: 10)
  of rrwShop, rrwNone: 0   # the shop is placed, never rolled

proc rewardCap(reward: RoomReward): int =
  ## Most offers of a reward per sector (counted across all doors shown).
  case reward
  of rrwDraft: 99
  of rrwShop: 1
  of rrwNone: 0
  of rrwCredits, rrwShards, rrwRepair, rrwPatch, rrwQuarantine: 2

proc generateFloor*(game: Game, theme: DungeonFloorTheme, floorNumber: int): DungeonFloor =
  ## Roll a sector: the exits of every layer, from the run seed alone. The
  ## random draws always happen in the same order, so the same seed rebuilds
  ## the same sector on resume.
  let run = game.rogueliteRun
  var rng = initRand(run.seed + floorNumber * 7919 + run.endlessLoop * 104729)
  let n = sectorLayerCount(floorNumber, run.endlessLoop)
  let shopLayer = (n + 1) div 2
  let patchLayer = 1 + rng.rand(1)
  # The first sector keeps /quarantine out of its first two layers: an elite
  # folder at layer 2 met a level-2 build and was the #1 early run-ender.
  let firstElite = if floorNumber <= 1 and run.endlessLoop == 0: 3 else: 2
  var eliteLayer = firstElite + rng.rand(max(0, n - 1 - firstElite))  # firstElite .. n-1
  if eliteLayer == shopLayer:
    eliteLayer = if shopLayer + 1 <= n - 1: shopLayer + 1 else: max(firstElite, shopLayer - 1)

  result = DungeonFloor(theme: theme, floorNumber: floorNumber,
                        layers: newSeq[DungeonLayer](n + 2),
                        path: @[0], rooms: @[], currentRoom: 0)
  result.layers[0].exits = @[DungeonExit(dir: ddDown, reward: rrwNone, kind: drkStart,
                                          encounterSeed: rng.rand(1_000_000_000),
                                          obstacleSeed: rng.rand(1_000_000_000))]

  var offered: array[RoomReward, int]
  for layer in 1..n:
    var picks: seq[RoomReward] = @[]
    if layer == shopLayer: picks.add(rrwShop)
    if layer == eliteLayer: picks.add(rrwQuarantine)
    if layer == patchLayer and rrwPatch notin picks: picks.add(rrwPatch)
    if layer == n and rrwRepair notin picks: picks.add(rrwRepair)
    let rolled = if layer == 1: 2
                 elif rng.rand(99) < threeExitChance(floorNumber): 3
                 else: 2
    let count = clamp(rolled, picks.len, 3)
    while picks.len < count:
      var total = 0
      for r in RoomReward:
        if r in picks or offered[r] >= rewardCap(r) or
           (r == rrwQuarantine and layer < firstElite):
          continue
        total += rewardWeight(r, floorNumber)
      if total <= 0:
        break
      var roll = rng.rand(total - 1)
      for r in RoomReward:
        if r in picks or offered[r] >= rewardCap(r) or
           (r == rrwQuarantine and layer < firstElite):
          continue
        roll -= rewardWeight(r, floorNumber)
        if roll < 0:
          picks.add(r)
          break
    rng.shuffle(picks)
    for r in picks:
      inc offered[r]
    let dirs =
      case picks.len
      of 1: @[ddUp]
      of 2: [@[ddLeft, ddRight], @[ddLeft, ddUp], @[ddUp, ddRight]][rng.rand(2)]
      else: @[ddLeft, ddUp, ddRight]
    for i, r in picks:
      result.layers[layer].exits.add(DungeonExit(
        dir: dirs[i], reward: r, kind: rewardRoomKind(r),
        encounterSeed: rng.rand(1_000_000_000),
        obstacleSeed: rng.rand(1_000_000_000)))

  # The last reward folder funnels into the sector's SERVICE.
  result.layers[n + 1].exits = @[DungeonExit(dir: ddUp, reward: rrwNone, kind: drkBoss,
                                              encounterSeed: rng.rand(1_000_000_000),
                                              obstacleSeed: rng.rand(1_000_000_000))]

proc dungeonDensityWave*(run: RogueliteRun, room: DungeonRoom): int =
  ## The wave-curve slot for a folder's CROWD SIZE (and the matching per-enemy
  ## rebate): its threat, i.e. roughly how many folders the player has grown
  ## through. Deliberately NOT dungeonRoomWaveEquivalent (threat x2.5), which
  ## calibrates enemy stat compression: using it here put wave-8 crowds in the
  ## third folder of a run, against a player two rooms old.
  max(1, dungeonEffectiveThreat(run, room) + 1)

proc encounterBudgetFor(run: RogueliteRun, room: DungeonRoom): int =
  let wave = dungeonDensityWave(run, room)
  var scale = if room.kind == drkElite: QuarantineCountScale else: RoomEnemyCountScale
  # Onboarding: the first sector's crowds are a notch lighter (a fresh build
  # has 9 integrity and no power-ups yet).
  if run.floorNumber <= 1 and run.endlessLoop == 0:
    scale *= FirstSectorCountScale
  max(8, int(calculateWaveEnemyCount(wave).float32 * scale))

proc buildRoom(run: RogueliteRun, floor: DungeonFloor, layer, exitIdx: int): DungeonRoom =
  let ex = floor.layers[layer].exits[exitIdx]
  result = DungeonRoom(layer: layer, exitIdx: exitIdx, kind: ex.kind, reward: ex.reward,
                       encounterSeed: ex.encounterSeed, obstacleSeed: ex.obstacleSeed,
                       pickups: @[])
  case ex.kind
  of drkCombat, drkElite:
    result.encounterBudget = encounterBudgetFor(run, result)
  of drkStart, drkShop:
    result.cleared = true
  of drkBoss:
    discard
  # Nothing to collect: the start room, SERVICE, and /pkg (stalls are optional).
  if result.reward in {rrwNone, rrwShop}:
    result.rewardClaimed = true

proc appendRoom*(game: Game, exitIdx: int): DungeonRoom =
  ## Walk into the next layer through `exitIdx`: extend the path and build the
  ## room it leads to (not yet entered).
  let run = game.rogueliteRun
  let floor = run.floor
  let layer = floor.rooms.len   # rooms[k] lives on layer k
  floor.path.add(exitIdx)
  result = buildRoom(run, floor, layer, exitIdx)
  floor.rooms.add(result)
  floor.currentRoom = floor.rooms.high

proc beginSectorRooms*(game: Game) =
  ## Place the start room of a freshly generated sector.
  let floor = game.rogueliteRun.floor
  floor.rooms = @[buildRoom(game.rogueliteRun, floor, 0, 0)]
  floor.path = @[0]
  floor.currentRoom = 0

# ---------------------------------------------------------------------------
# Theme selection between sectors


proc isFinalDungeonFloor*(run: RogueliteRun): bool =
  ## The final sector offers one special "final boss" arena (always boss 12)
  ## instead of a three-theme roll. Gates generation, rendering and input.
  not run.isNil and run.floorNumber >= RogueliteFloorsToWin

proc generateThemeChoices*(run: RogueliteRun) =
  if run.isNil: return
  if isFinalDungeonFloor(run):
    # Final sector: no roll. A single fixed arena that always headlines the
    # Omega Entity. Every slot resolves to it so any selection index lands on
    # the same theme, and the theme-select UI renders one special card.
    for i in 0 .. 2:
      run.nextThemeChoices[i] = FinalFloorTheme
    return
  # The final sector's theme never rolls here: it belongs to the Omega Entity.
  var pool: seq[DungeonFloorTheme] = @[]
  for theme in DungeonFloorTheme:
    if theme notin run.usedThemes and theme != FinalFloorTheme:
      pool.add(theme)
  if pool.len < 3:
    # Endless loops re-open the full pool.
    pool = @[]
    for theme in DungeonFloorTheme:
      if theme != FinalFloorTheme:
        pool.add(theme)

  # Offer 3 themes whose SERVICE bosses are all DISTINCT. Group the pool by
  # the boss each theme maps to in this sector, then draw one theme from 3
  # distinct boss-groups; if the band has fewer than 3 bosses the remaining
  # slots fall back to leftover themes (distinct themes, repeated boss).
  var groups = initTable[int, seq[DungeonFloorTheme]]()
  var bossOrder: seq[int] = @[]
  for theme in pool:
    let boss = dungeonBossNumberFor(theme, run.floorNumber, run.endlessLoop, run.heat)
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
# Pickups: rewards and stalls

proc newPickup(kind: DungeonPickupKind, pos: Vector2f): DungeonPickup =
  DungeonPickup(pos: pos, kind: kind, taken: false, patch: rrtNone)

proc isStall*(kind: DungeonPickupKind): bool =
  kind in {dpkStallPowerUp, dpkStallPatch, dpkStallRepair, dpkStallRestock}

proc isInteractPickup(kind: DungeonPickupKind): bool =
  ## Needs [E] (a choice or a purchase) rather than a touch.
  kind == dpkPatchPedestal or isStall(kind)

proc stallScale(run: RogueliteRun): float32 =
  ## Per-sector price growth, solved against measured credit income (sim):
  ## a sector's income should buy roughly one or two stalls, not the room.
  1.0'f32 + 0.55'f32 * (run.floorNumber - 1).float32 + 0.8'f32 * run.endlessLoop.float32

proc roundTo5(x: float32): int =
  max(5, int(round(x / 5.0'f32)) * 5)

proc stallNextLevel(game: Game, pickup: DungeonPickup): int =
  ## The level a power-up stall would install now, or 0 when it is maxed.
  ## Derived live: a level-up draft may have raised it since the stall rolled.
  let pt = pickup.powerUp.powerType
  let next = getPowerUpLevel(game.player, pt) + 1
  if next > getPowerUpMaxLevel(pt): 0 else: next

proc stallPrice*(game: Game, room: DungeonRoom, pickup: DungeonPickup): int =
  let run = game.rogueliteRun
  let base =
    case pickup.kind
    of dpkStallPowerUp: 55.0'f32 + 20.0'f32 * max(0, stallNextLevel(game, pickup) - 1).float32
    of dpkStallPatch: 95.0'f32
    of dpkStallRepair: 40.0'f32
    of dpkStallRestock: 20.0'f32 + 20.0'f32 * room.restocks.float32
    else: 0.0'f32
  if base <= 0: 0
  else: patchPrice(game.player, roundTo5(base * stallScale(run)))

proc stallPowerUpOffers(game: Game, count: int, exclude: set[PowerUpType]): seq[PowerUp] =
  ## Up to `count` distinct, installable common power-ups for /pkg stalls.
  let choices = generatePowerUpChoices(game.player, false, AllPowerFamilies, gmRoguelite)
  var seen = exclude
  for c in choices:
    if result.len >= count: break
    if c.level <= 0 or c.powerType in seen: continue
    seen.incl(c.powerType)
    result.add(c)

proc shardCacheAmount(run: RogueliteRun): int =
  let heatRank = heatChallengeRank(run.heat)
  let magnet = if run.hasRelic(rrtShardMagnet): 1.0'f32 + ShardMagnetBonus else: 1.0'f32
  int(ceil((14 + run.floorNumber * 4 + heatRank * 5 + run.endlessLoop * 8).float32 *
           themeDef(run.floor.theme).shardMod * magnet))

proc refreshRewardClaimed(room: DungeonRoom) =
  ## A folder's reward is claimed once none of its reward pickups remain
  ## (stalls never block the exits).
  if room.isNil or room.rewardClaimed: return
  for p in room.pickups:
    if not p.taken and not isStall(p.kind):
      return
  room.rewardClaimed = true

proc spawnShardFallback(game: Game, room: DungeonRoom) =
  let p = newPickup(dpkShardCache, roomCenter(game))
  p.amount = shardCacheAmount(game.rogueliteRun)
  room.pickups.add(p)

proc spawnPatchChoice(game: Game, room: DungeonRoom, group: int) =
  ## Three patch pedestals in a row; applying one dissolves the others.
  let choices = rollPatchChoices(game.rogueliteRun, 3)
  if choices.len == 0:
    spawnShardFallback(game, room)
    return
  let c = roomCenter(game)
  for i, p in choices:
    let offset = (i.float32 - (choices.len - 1).float32 * 0.5'f32) * 130.0'f32
    let pk = newPickup(dpkPatchPedestal, newVector2f(c.x + offset, c.y))
    pk.patch = p
    pk.group = group
    room.pickups.add(pk)

proc spawnRoomReward*(game: Game, room: DungeonRoom) =
  ## Materialize what a cleared folder pays, in the middle of the room.
  if room.isNil or room.rewardSpawned: return
  room.rewardSpawned = true
  let run = game.rogueliteRun
  let c = roomCenter(game)
  case room.reward
  of rrwNone, rrwShop:
    discard
  of rrwDraft:
    room.pickups.add(newPickup(dpkDraftPackage, c))
  of rrwPatch, rrwQuarantine:
    spawnPatchChoice(game, room, 1)
  of rrwCredits:
    let heatRank = heatChallengeRank(run.heat)
    let p = newPickup(dpkCreditCache, c)
    p.amount = 35 + 12 * run.floorNumber + 6 * heatRank + 15 * run.endlessLoop
    room.pickups.add(p)
  of rrwRepair:
    let p = newPickup(dpkRepairKit, c)
    p.amount = RepairRewardPercent
    room.pickups.add(p)
  of rrwShards:
    spawnShardFallback(game, room)
  if room.pickups.len == 0:
    room.rewardClaimed = true
  refreshRewardClaimed(room)

proc stallPositions(game: Game): array[5, Vector2f] =
  let c = roomCenter(game)
  const xs = [-250'f32, -125'f32, 0'f32, 125'f32, 250'f32]
  const ys = [34'f32, 8'f32, -6'f32, 8'f32, 34'f32]
  for i in 0..4:
    result[i] = newVector2f(c.x + xs[i], c.y - 30 + ys[i])

proc spawnShopStalls*(game: Game, room: DungeonRoom) =
  ## /pkg: two power-up packages, a patch, a repair and a restock, in an arc.
  if room.isNil or room.rewardSpawned: return
  room.rewardSpawned = true
  let pos = stallPositions(game)
  let offers = stallPowerUpOffers(game, 2, {})
  var slot = 0
  for o in offers:
    let p = newPickup(dpkStallPowerUp, pos[slot])
    p.powerUp = o
    p.spawnTimer = PickupSpawnTime
    room.pickups.add(p)
    inc slot
  slot = max(slot, 2)
  let patchRoll = rollPatchChoices(game.rogueliteRun, 1)
  if patchRoll.len > 0:
    let p = newPickup(dpkStallPatch, pos[2])
    p.patch = patchRoll[0]
    p.spawnTimer = PickupSpawnTime
    room.pickups.add(p)
  let repair = newPickup(dpkStallRepair, pos[3])
  repair.amount = RepairRewardPercent
  repair.spawnTimer = PickupSpawnTime
  room.pickups.add(repair)
  let restock = newPickup(dpkStallRestock, pos[4])
  restock.spawnTimer = PickupSpawnTime
  room.pickups.add(restock)

proc restockStalls(game: Game, room: DungeonRoom) =
  ## Reroll every unsold power-up and patch stall to something new.
  var current: set[PowerUpType] = {}
  var currentPatches: set[RogueliteRelicType] = {}
  for p in room.pickups:
    if p.kind == dpkStallPowerUp: current.incl(p.powerUp.powerType)
    if p.kind == dpkStallPatch: currentPatches.incl(p.patch)
  for p in room.pickups:
    if p.taken: continue
    case p.kind
    of dpkStallPowerUp:
      let fresh = stallPowerUpOffers(game, 1, current)
      if fresh.len > 0:
        p.powerUp = fresh[0]
        current.incl(fresh[0].powerType)
        p.spawnTimer = 0
    of dpkStallPatch:
      let fresh = rollPatchChoices(game.rogueliteRun, 1, currentPatches)
      if fresh.len > 0:
        p.patch = fresh[0]
        currentPatches.incl(fresh[0])
        p.spawnTimer = 0
    else:
      discard

# ---------------------------------------------------------------------------
# Room state changes

proc wipeRoomEntities*(game: Game) =
  ## Rooms do not persist live entities; clear everything transient.
  game.enemies = @[]
  game.bullets = @[]
  game.coins = @[]
  game.xpOrbs = @[]
  game.consumables = @[]
  game.attackWarnings = @[]
  game.lasers = @[]
  game.meteorites = @[]
  game.lightningBolts = @[]
  game.shockwaveRings = @[]
  game.pathShockwaves = @[]
  game.bossDeathBlasts = @[]
  game.walls = @[]
  game.pendingWallRespawns = @[]
  game.pendingBoss = nil
  game.pendingBossTimer = 0
  game.bossSpawnTimer = 0
  # Roster state tied to the room: corpses a Restorer could raise, husks, the
  # Hive's freeze.
  game.modeCombat.corpses = @[]
  game.modeCombat.husks = @[]
  game.modeCombat.auditTimer = 0

proc spawnRoomObstacles(game: Game, room: DungeonRoom) =
  ## A few permanent circular obstacles, kept away from doors and the center.
  let def = themeDef(game.rogueliteRun.floor.theme)
  var rng = initRand(room.obstacleSeed)
  var count = def.obstacleMin + rng.rand(max(0, def.obstacleMax - def.obstacleMin))
  # The Gatekeeper's searchlights and the Supervisor's page faults are played
  # around cover: their SERVICE rooms always get enough of it.
  if room.kind == drkBoss and dungeonBossNumber(game) in [17, 21]:
    count = max(count, 4)
  let w = game.screenWidth.float32
  let h = game.screenHeight.float32
  var attempts = 0
  var placed = 0
  while placed < count and attempts < 60:
    inc attempts
    let x = 130'f32 + rng.rand(1.0).float32 * (w - 260'f32)
    let y = 120'f32 + rng.rand(1.0).float32 * (h - 240'f32)
    let pos = newVector2f(x, y)
    # Keep the center (reward drop) and every door lane free
    if abs(x - w / 2) < 170 and abs(y - h / 2) < 120: continue
    if abs(x - w / 2) < 110 and (y < 170 or y > h - 170): continue
    if abs(y - h / 2) < 110 and (x < 170 or x > w - 170): continue
    var tooClose = false
    for wall in game.walls:
      if distance(pos, wall.pos) < 90:
        tooClose = true
        break
    if tooClose: continue
    # Boss-room obstacles re-form after the boss smashes them; combat-room ones
    # are gone for good once enemies break through. HP grows with sector depth
    # (and endless loops) so late walls don't shatter instantly against the
    # bigger, faster crowds down there.
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
  let waveScaling = RoomScalingPerRoom
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

proc armRoomPatches(game: Game, room: DungeonRoom) =
  ## Per-room patch charges, re-armed on entering an uncleared fight.
  if hasPatch(game.player, rrtFirewallRule):
    game.player.patchBlockCharges = max(game.player.patchBlockCharges, 1)
  if room.kind == drkBoss and hasPatch(game.player, rrtEmergencyPatch):
    game.player.patchBlockCharges += 1
  if hasPatch(game.player, rrtCronJob):
    game.player.cronJobTimer = CronJobInterval

proc initRoomPulses(room: DungeonRoom) =
  room.pulseCount = clamp(room.encounterBudget div PulseEnemies, 2, 5)
  room.pulseIndex = 0
  room.pulseQuota = 0
  room.pulseSize = 0
  room.pulseTimer = PulseFirstDelay

proc startNextPulse(room: DungeonRoom) =
  inc room.pulseIndex
  let base = room.encounterBudget div room.pulseCount
  # The remainder lands in the final pulse, so the sizes always sum to the budget.
  room.pulseSize = if room.pulseIndex >= room.pulseCount:
                     room.encounterBudget - base * (room.pulseCount - 1)
                   else: base
  room.pulseQuota = room.pulseSize
  room.pulseTimer = 0

proc updateRoomPulse(game: Game, room: DungeonRoom, dt: float32) =
  ## Release the encounter in pulses: the first after a short beat, each next
  ## one once the last is mostly dead (or after PulseMaxGap regardless).
  if room.kind notin {drkCombat, drkElite} or room.cleared or not game.waveInProgress:
    return
  if room.pulseQuota > 0 or room.pulseIndex >= room.pulseCount:
    return
  if room.pulseIndex == 0:
    room.pulseTimer -= dt
    if room.pulseTimer <= 0:
      startNextPulse(room)
    return
  room.pulseTimer += dt
  if game.enemies.len.float32 <= PulseAliveFraction * room.pulseSize.float32 or
     room.pulseTimer >= PulseMaxGap:
    startNextPulse(room)

proc dungeonSpawnAllowance*(game: Game): int =
  ## How many more enemies the live pulse may still spawn (game.nim's spawner
  ## never exceeds this).
  let room = currentDungeonRoom(game.rogueliteRun)
  if room.isNil or room.kind notin {drkCombat, drkElite}: 0
  else: max(0, room.pulseQuota)

proc consumeDungeonSpawn*(game: Game) =
  let room = currentDungeonRoom(game.rogueliteRun)
  if not room.isNil and room.pulseQuota > 0:
    dec room.pulseQuota

proc enterRoom*(game: Game, roomIdx: int, enteredThrough: DoorDir,
                resumed: bool = false) =
  ## Swap the live arena to the given room. Called mid-transition.
  ##
  ## `resumed` re-enters the room a saved run was in. That save already holds
  ## the player stats this room's scaling produced when it was first entered,
  ## so applying it again would compound it on every resume.
  let run = game.rogueliteRun
  let floor = run.floor
  floor.currentRoom = clamp(roomIdx, 0, floor.rooms.high)
  let room = floor.rooms[floor.currentRoom]
  focusedPickup = -1

  wipeRoomEntities(game)
  game.player.pos = if room.kind == drkStart: roomCenter(game)
                    else: doorSpawnPos(game, enteredThrough)
  game.player.vel = newVector2f(0, 0)
  run.roomDensityWave = dungeonDensityWave(run, room)

  if room.kind in {drkCombat, drkElite, drkBoss}:
    spawnRoomObstacles(game, room)
  if room.kind == drkShop:
    spawnShopStalls(game, room)

  if room.cleared:
    game.waveInProgress = false
    game.waveEnemiesRemaining = 0
    game.waveEnemiesTotal = 0
    return

  armRoomPatches(game, room)
  case room.kind
  of drkBoss:
    # Boss rooms arm the boss-spawn machinery instead of a normal encounter.
    if not resumed:
      applyRoomScaling(game)
    game.waveInProgress = true
    game.waveEnemiesTotal = 0
    game.waveEnemiesRemaining = 0
    game.wavesUntilBoss = 0
    game.spawnTimer = 0
  of drkCombat, drkElite:
    if not resumed:
      applyRoomScaling(game)
    game.waveInProgress = true
    game.waveEnemiesTotal = room.encounterBudget
    game.waveEnemiesRemaining = room.encounterBudget
    game.wavesUntilBoss = 999
    game.spawnTimer = 0
    game.waveStartTime = game.time
    initRoomPulses(room)
  of drkStart, drkShop:
    game.waveInProgress = false
    room.cleared = true

proc startDungeonFloor*(game: Game, theme: DungeonFloorTheme) =
  ## Build the sector for the chosen theme and place the player in its start room.
  let run = game.rogueliteRun
  run.usedThemes.incl(theme)
  run.pendingFloorSelect = false
  game.bossPortalActive = false
  game.bossPortalTimer = 0
  run.floor = generateFloor(game, theme, run.floorNumber)
  beginSectorRooms(game)
  game.waveInProgress = false
  game.waveEnemiesRemaining = 0
  game.waveEnemiesTotal = 0
  game.wavesUntilBoss = 999
  game.spawnTimer = 0
  game.roomTransitionActive = false
  game.roomTransitionTimer = 0
  # Rollback re-arms once per sector.
  game.player.rollbackArmed = hasPatch(game.player, rrtRollback)
  enterRoom(game, 0, ddDown)

proc selectFloorTheme*(game: Game, choiceIndex: int) =
  if game.rogueliteRun.isNil: return
  let idx = clamp(choiceIndex, 0, 2)
  startDungeonFloor(game, game.rogueliteRun.nextThemeChoices[idx])

proc onRoomCleared*(game: Game) =
  ## Combat/quarantine folder finished: vacuum the loot, pay the per-folder
  ## shards (and the quarantine bonus), then materialize the folder's reward.
  ## game.nim banks level-ups right after this, with the XP already counted.
  let run = game.rogueliteRun
  let room = currentDungeonRoom(run)
  if room.isNil or room.cleared: return

  collectAllCoins(game)
  collectAllXpOrbs(game)
  room.cleared = true
  game.waveInProgress = false
  run.totalRoomsCleared += 1
  playSound(stWaveComplete)

  let def = themeDef(run.floor.theme)
  let heatRank = heatChallengeRank(run.heat)
  let magnet = if run.hasRelic(rrtShardMagnet): 1.0'f32 + ShardMagnetBonus else: 1.0'f32
  let shardMult = def.shardMod * magnet
  var shardBonus = int(ceil((3 + run.floorNumber + heatRank * 2 +
                             run.endlessLoop * 2).float32 * shardMult))

  if room.kind == drkElite:
    shardBonus += int(ceil((6 + run.floorNumber * 2).float32 * shardMult))
    var credits = 12 + run.floorNumber * 5 + heatRank * 4
    if run.hasRelic(rrtEliteDividend):
      credits += EliteDividendCredits
      shardBonus += int(ceil(EliteDividendShards.float32 * shardMult))
    game.player.coins += credits
    showCurrency(game, game.player.pos + newVector2f(-24, -28), credits, cikCredits)
    if heatRank > 0:
      run.coresEarned += heatRank + run.endlessLoop
      showCurrency(game, game.player.pos + newVector2f(22, -20),
                   heatRank + run.endlessLoop, cikCores)

  run.shardsEarned += max(1, shardBonus)
  showCurrency(game, game.player.pos + newVector2f(0, -36), max(1, shardBonus), cikDataShards)

  # Defragmenter patch: a cleared folder compacts integrity back.
  if hasPatch(game.player, rrtDefragmenter):
    let restored = heal(game.player, game.player.maxHp * DefragmenterRoomHeal)
    if restored > 0:
      showDamage(game, game.player.pos, restored, true, false, dtHeal)

  spawnRoomReward(game, room)

proc markBossRoomCleared*(game: Game) =
  ## Called from the boss-defeated handler in game.nim, before level banking.
  let run = game.rogueliteRun
  if run.isNil or run.floor.isNil: return
  let room = currentDungeonRoom(run)
  if not room.isNil and room.kind == drkBoss and not room.cleared:
    room.cleared = true
    room.rewardClaimed = true
    run.totalRoomsCleared += 1
    if hasPatch(game.player, rrtDefragmenter):
      let restored = heal(game.player, game.player.maxHp * DefragmenterBossHeal)
      if restored > 0:
        showDamage(game, game.player.pos, restored, true, false, dtHeal)
  collectAllCoins(game)
  collectAllXpOrbs(game)
  game.waveInProgress = false

proc exitPortalPos*(game: Game): Vector2f =
  ## The boss-clear portal always forms at the center of the SERVICE room.
  roomCenter(game)

proc spawnRogueliteExitPortal*(game: Game) =
  ## Open the swirling exit portal in the cleared SERVICE room. The sector only
  ## advances once the player physically steps into it (see updateDungeon).
  game.bossPortalActive = true
  game.bossPortalTimer = 0
  playSound(stBossSpawn, 0.7)

# ---------------------------------------------------------------------------
# Claiming pickups

proc openRewardDraft(game: Game) =
  ## A /bin install package: the standard installer draft, opened in place.
  game.powerUpChoices = generatePowerUpChoices(game.player, false, AllPowerFamilies, game.mode)
  game.selectedPowerUp = 0
  initPowerUpRollAnimation(game)
  initializeRerollCost(game)
  game.state = gsPowerUpSelect

proc announcePatch(game: Game, patch: RogueliteRelicType) =
  showPerk(game, game.player.pos + newVector2f(0, -44),
           patchKbLabel(patch) & " " & t("patch_applied"), patchAccent(patch))
  spawnExplosionPooled(game.particlePool, game.player.pos.x, game.player.pos.y, patchAccent(patch), 28)
  playSound(stPowerUp, 0.85)

proc claimDungeonPickup*(game: Game, index: int): DungeonFrame =
  ## Apply one pickup of the live room (touch or [E]). Stalls charge credits
  ## and refuse when unaffordable. Shared by the input path and test harnesses.
  let run = game.rogueliteRun
  let room = currentDungeonRoom(run)
  if room.isNil or index < 0 or index >= room.pickups.len: return
  let pickup = room.pickups[index]
  if pickup.taken: return

  if isStall(pickup.kind):
    let price = stallPrice(game, room, pickup)
    if game.player.coins < price:
      playSound(stMenuSelect, 0.4)
      return
    case pickup.kind
    of dpkStallPowerUp:
      let lvl = stallNextLevel(game, pickup)
      if lvl <= 0:
        return
      game.player.coins -= price
      pickup.taken = true
      let rarity = if allPowerUpDefs[pickup.powerUp.powerType].pool == puppLegendary: prLegendary
                   else: prCommon
      result.install = PowerUp(powerType: pickup.powerUp.powerType, level: lvl, rarity: rarity)
    of dpkStallPatch:
      if not installPatch(game, pickup.patch):
        return
      game.player.coins -= price
      pickup.taken = true
      announcePatch(game, pickup.patch)
    of dpkStallRepair:
      game.player.coins -= price
      pickup.taken = true
      let restored = heal(game.player, game.player.maxHp * pickup.amount.float32 / 100.0'f32)
      if restored > 0:
        showDamage(game, game.player.pos, restored, true, false, dtHeal)
      playSound(stPowerUp, 0.6)
    of dpkStallRestock:
      game.player.coins -= price
      inc room.restocks
      restockStalls(game, room)
      playSound(stMenuSelect, 0.8)
    else:
      discard
    playSound(stBuy, 0.7)
    result.checkpoint = true
    return

  case pickup.kind
  of dpkDraftPackage:
    pickup.taken = true
    openRewardDraft(game)
    result.pauseSim = true
  of dpkPatchPedestal:
    if not installPatch(game, pickup.patch):
      return
    pickup.taken = true
    # The other updates in this offer are declined.
    for other in room.pickups:
      if other != pickup and other.group != 0 and other.group == pickup.group and not other.taken:
        other.taken = true
        spawnExplosionPooled(game.particlePool, other.pos.x, other.pos.y, Color(r: 120, g: 140, b: 170, a: 255), 12)
    announcePatch(game, pickup.patch)
  of dpkCreditCache:
    pickup.taken = true
    game.player.coins += pickup.amount
    showCurrency(game, pickup.pos, pickup.amount, cikCredits)
    playSound(stCoinPickup, 0.8)
  of dpkRepairKit:
    pickup.taken = true
    let restored = heal(game.player, game.player.maxHp * pickup.amount.float32 / 100.0'f32)
    if restored > 0:
      showDamage(game, game.player.pos, restored, true, false, dtHeal)
    playSound(stPowerUp, 0.6)
  of dpkShardCache:
    pickup.taken = true
    run.shardsEarned += pickup.amount
    showCurrency(game, pickup.pos, pickup.amount, cikDataShards)
    playSound(stCoinPickup, 0.8)
  else:
    discard
  refreshRewardClaimed(room)
  result.checkpoint = true

# ---------------------------------------------------------------------------
# Per-frame update: transitions, pulses, pickups, doors

proc interactPressed(): bool =
  isKeyPressed(globalSettings.keybinds[kaPlaceWall]) or isKeyPressed(Enter) or
    isGamepadBindPressed(globalSettings.gamepadBinds, kaPlaceWall)

proc updateDungeon*(game: Game, dt: float32): DungeonFrame =
  ## One frame of sector logic. `pauseSim` means gameplay should skip the rest
  ## of this frame (a room transition is running, or a modal just opened).
  game.dungeonInteractFocus = false
  let run = game.rogueliteRun
  if run.isNil or run.floor.isNil: return
  let floor = run.floor

  if game.roomTransitionActive:
    result.pauseSim = true
    let prev = game.roomTransitionTimer
    game.roomTransitionTimer += dt
    let half = RoomTransitionDuration / 2
    if prev < half and game.roomTransitionTimer >= half:
      # Midpoint: take the exit while the screen is dark.
      let room = currentDungeonRoom(run)
      let exits = exitsOf(floor, room)
      for i, ex in exits:
        if ex.dir == game.roomTransitionDir:
          discard appendRoom(game, i)
          enterRoom(game, floor.rooms.high, ddDown)
          result.checkpoint = true
          break
    if game.roomTransitionTimer >= RoomTransitionDuration:
      game.roomTransitionActive = false
      game.roomTransitionTimer = 0
    return

  let room = currentDungeonRoom(run)
  if room.isNil: return

  updateRoomPulse(game, room, dt)

  # SERVICE-clear exit portal: the sector only advances once the player walks
  # into it. It animates in first (spawn animation) before becoming enterable.
  if game.bossPortalActive and room.kind == drkBoss:
    game.bossPortalTimer += dt
    if game.bossPortalTimer >= ExitPortalSpawnDuration and
       distance(game.player.pos, exitPortalPos(game)) < ExitPortalRadius + game.player.radius:
      game.bossPortalActive = false
      playSound(stTeleport)
      generateThemeChoices(run)
      game.selectedRogueliteTheme = 0
      game.state = gsRogueliteFloorSelect
      result.pauseSim = true
      return

  # Pickups. Level-up drafts owed from this clear resolve first, so a reward
  # draft can never stack under (or race) a level-up one.
  let canClaim = game.state == gsPlaying and game.pendingLevelDrafts <= 0 and
                 game.levelDraftDelay <= 0
  var nearest = -1
  var nearestDist = InteractRadius + game.player.radius
  for i, pickup in room.pickups:
    if pickup.taken: continue
    pickup.spawnTimer += dt
    if pickup.spawnTimer < PickupSpawnTime: continue
    let d = distance(game.player.pos, pickup.pos)
    if isInteractPickup(pickup.kind):
      if d < nearestDist:
        nearestDist = d
        nearest = i
    else:
      # Touch rewards drift to the player so none is ever walked past.
      if pickup.spawnTimer >= PickupMagnetDelay and d > 1.0'f32:
        let step = min(d, PickupMagnetSpeed * dt)
        pickup.pos = pickup.pos + (game.player.pos - pickup.pos) * (step / d)
      if canClaim and distance(game.player.pos, pickup.pos) < PickupRadius + game.player.radius:
        let r = claimDungeonPickup(game, i)
        result.checkpoint = result.checkpoint or r.checkpoint
        if r.pauseSim:
          result.pauseSim = true
          return
  focusedPickup = nearest
  if nearest >= 0:
    game.dungeonInteractFocus = true
    if canClaim and interactPressed():
      game.interactKeyLatch = true
      let r = claimDungeonPickup(game, nearest)
      result.install = r.install
      result.checkpoint = result.checkpoint or r.checkpoint
      # The [E] press is spent: skip the rest of this frame's gameplay so it
      # can't also count as a wall-placement press.
      result.pauseSim = true
      return

  # Door traversal once the folder is cleared and its reward collected.
  if exitsOpen(room):
    let playerRect = Rectangle(
      x: game.player.pos.x - game.player.radius,
      y: game.player.pos.y - game.player.radius,
      width: game.player.radius * 2,
      height: game.player.radius * 2)
    for ex in exitsOf(floor, room):
      if checkCollisionRecs(playerRect, doorRect(game, ex.dir)):
        game.roomTransitionActive = true
        game.roomTransitionTimer = 0
        game.roomTransitionDir = ex.dir
        playSound(stMenuSelect, 0.6)
        result.pauseSim = true
        return

# ---------------------------------------------------------------------------
# HUD helpers

proc sectorPath*(floor: DungeonFloor): string =
  ## Breadcrumb of the folders taken so far: C:\FIREWALL\bin\cache\
  if floor.isNil: return ""
  result = "C:\\" & themeFolder(floor.theme) & "\\"
  for room in floor.rooms:
    case room.kind
    of drkStart: discard
    of drkBoss: result &= "service\\"
    else: result &= rewardFolderKey(room.reward) & "\\"

# ---------------------------------------------------------------------------
# Drawing: doors, pickups, cards, portal, transition fade

proc drawFolderTab(x, y, w, h: float32, color: Color, fillAlpha: uint8) =
  ## Folder silhouette: a body with a tab on its top-left.
  let tabW = w * 0.42'f32
  drawRectangle(Rectangle(x: x, y: y - 5, width: tabW, height: 6), withAlpha(color, fillAlpha))
  drawRectangle(Rectangle(x: x, y: y, width: w, height: h), withAlpha(color, fillAlpha))
  drawRectangleLines(Rectangle(x: x, y: y, width: w, height: h), 1.5, withAlpha(color, 230))

proc drawExitDoor(game: Game, ex: DungeonExit, open: bool, bossNumber: int) =
  let rect = doorRect(game, ex.dir)
  let accent = if ex.kind == drkBoss: Color(r: 255, g: 90, b: 70, a: 255)
               else: rewardAccent(ex.reward)
  let pulse = 0.6'f32 + 0.4'f32 * sin(game.time * 3.4'f32)
  let alphaK = if open: 1.0'f32 else: 0.38'f32
  drawRectangle(rect, withAlpha(accent, uint8(70.0'f32 * alphaK * (if open: pulse else: 1.0'f32))))
  drawRectangleLines(rect, 2.0, withAlpha(accent, uint8(235.0'f32 * alphaK)))

  # Label card just inside the door.
  const cardW = 150'f32
  const cardH = 58'f32
  let w = game.screenWidth.float32
  let h = game.screenHeight.float32
  var cx, cy: float32
  case ex.dir
  of ddUp:
    cx = w / 2 - cardW / 2
    cy = DoorZoneDepth + 12
  of ddLeft:
    cx = DoorZoneDepth + 12
    cy = h / 2 - cardH / 2
  of ddRight:
    cx = w - DoorZoneDepth - 12 - cardW
    cy = h / 2 - cardH / 2
  of ddDown:
    cx = w / 2 - cardW / 2
    cy = h - DoorZoneDepth - 12 - cardH
  let fillA = uint8(if open: 44 else: 20)
  drawRectangle(Rectangle(x: cx, y: cy, width: cardW, height: cardH),
                Color(r: 10, g: 14, b: 22, a: uint8(200.0'f32 * alphaK + 30)))
  drawFolderTab(cx + 6, cy + 11, 38, 32, accent, fillA)
  let iconA = uint8(if open: 255 else: 120)
  if ex.kind == drkBoss:
    drawServiceIcon((cx + 9).int32, (cy + 13).int32, 32, withAlpha(accent, iconA))
  else:
    drawRoomRewardIcon((cx + 9).int32, (cy + 13).int32, 32, ex.reward, withAlpha(accent, iconA))
  let name = if ex.kind == drkBoss: "/service" else: rewardFolderName(ex.reward)
  let sub = if ex.kind == drkBoss: bossName(bossNumber)
            else: rewardLabel(ex.reward)
  let textX = (cx + 52).int32
  let textW = (cardW - 58).int32
  drawTextFit(name, textX, (cy + 10).int32, textW, 16,
              withAlpha(if open: RayWhite else: Gray, iconA), 10)
  drawTextFit(sub, textX, (cy + 31).int32, textW, 12, withAlpha(accent, iconA), 8)
  if not open:
    drawLockIcon((cx + cardW - 18).int32, (cy + 4).int32, 13, withAlpha(accent, 200))

proc drawEntryDoor(game: Game) =
  ## The door the player came in by: closed behind them (no going back).
  let rect = doorRect(game, ddDown)
  drawRectangle(rect, Color(r: 60, g: 66, b: 80, a: 90))
  drawRectangleLines(rect, 1.5, Color(r: 110, g: 118, b: 136, a: 160))
  let midY = (rect.y + rect.height / 2).int32
  drawLine((rect.x + 18).int32, midY, (rect.x + rect.width - 18).int32, midY,
           Color(r: 130, g: 138, b: 156, a: 160))

proc drawPedestalBase(pos: Vector2f, accent: Color, time: float32) =
  drawEllipse(pos.x.int32, (pos.y + 18).int32, 24, 8, Color(r: 0, g: 0, b: 0, a: 90))
  drawEllipse(pos.x.int32, (pos.y + 15).int32, 22, 7, Color(r: 22, g: 30, b: 44, a: 235))
  drawEllipseLines(pos.x.int32, (pos.y + 15).int32, 22, 7, withAlpha(accent, 190))

proc drawPickup(game: Game, room: DungeonRoom, index: int, pickup: DungeonPickup) =
  let t = clamp(pickup.spawnTimer / PickupSpawnTime, 0.0'f32, 1.0'f32)
  let grow = 1.0'f32 - pow(1.0'f32 - t, 3.0'f32)
  let bob = sin(game.time * 2.6'f32 + index.float32) * 3.0'f32
  let accent =
    case pickup.kind
    of dpkPatchPedestal, dpkStallPatch: patchAccent(pickup.patch)
    of dpkDraftPackage: rewardAccent(rrwDraft)
    of dpkStallPowerUp: getPowerUpColor(pickup.powerUp.powerType)
    of dpkCreditCache: rewardAccent(rrwCredits)
    of dpkRepairKit, dpkStallRepair: rewardAccent(rrwRepair)
    of dpkShardCache: rewardAccent(rrwShards)
    of dpkStallRestock: rewardAccent(rrwShop)
  # Materialize beam.
  if t < 1.0'f32:
    let beamA = uint8(150.0'f32 * (1.0'f32 - t))
    drawRectangle((pickup.pos.x - 10).int32, 0, 20, pickup.pos.y.int32, withAlpha(accent, beamA div 3))
  let isFocus = index == focusedPickup
  if isInteractPickup(pickup.kind):
    drawPedestalBase(pickup.pos, accent, game.time)
  let size = int32(34.0'f32 * grow * (if isFocus: 1.12'f32 else: 1.0'f32))
  let ix = (pickup.pos.x - size.float32 / 2).int32
  let iy = (pickup.pos.y - size.float32 / 2 - 6 + bob).int32
  drawCircle(Vector2(x: pickup.pos.x, y: pickup.pos.y - 6 + bob), size.float32 * 0.7'f32,
             withAlpha(accent, uint8(if isFocus: 60 else: 34)))
  case pickup.kind
  of dpkPatchPedestal, dpkStallPatch:
    drawPatchIcon(ix, iy, size, pickup.patch, accent)
  of dpkDraftPackage:
    drawRoomRewardIcon(ix, iy, size, rrwDraft, accent)
  of dpkStallPowerUp:
    drawPowerUpIcon(ix, iy, size, pickup.powerUp.powerType, accent)
  of dpkCreditCache:
    drawCurrencyIcon(pickup.pos.x.int32, (pickup.pos.y - 6 + bob).int32, size, ciCredits)
  of dpkShardCache:
    drawCurrencyIcon(pickup.pos.x.int32, (pickup.pos.y - 6 + bob).int32, size, ciDataShards)
  of dpkRepairKit, dpkStallRepair:
    drawRoomRewardIcon(ix, iy, size, rrwRepair, accent)
  of dpkStallRestock:
    drawRoomRewardIcon(ix, iy, size, rrwShop, accent)

  # Price tags under the stalls.
  if isStall(pickup.kind) and t >= 1.0'f32:
    let price = stallPrice(game, room, pickup)
    let maxed = pickup.kind == dpkStallPowerUp and stallNextLevel(game, pickup) <= 0
    let label = if maxed: t("card_maxed") else: $price
    let lw = measureText(label, 13)
    let tagW = lw + (if maxed: 10 else: 24)
    let tx = pickup.pos.x.int32 - tagW div 2
    let ty = (pickup.pos.y + 26).int32
    drawRectangle(tx, ty, tagW, 18, Color(r: 12, g: 16, b: 24, a: 225))
    let affordable = game.player.coins >= price and not maxed
    let tagColor = if maxed: Color(r: 130, g: 136, b: 150, a: 255)
                   elif affordable: Color(r: 255, g: 215, b: 80, a: 255)
                   else: Color(r: 255, g: 110, b: 100, a: 255)
    drawRectangleLines(Rectangle(x: tx.float32, y: ty.float32, width: tagW.float32, height: 18),
                       1.0, withAlpha(tagColor, 180))
    if maxed:
      drawText(label, tx + 5, ty + 3, 13, tagColor)
    else:
      drawCurrencyIcon(tx + 10, ty + 9, 13, ciCredits)
      drawText(label, tx + 19, ty + 3, 13, tagColor)

proc pickupCard(game: Game, room: DungeonRoom, pickup: DungeonPickup): ProximityCard =
  result.accent = patchAccent(pickup.patch)
  case pickup.kind
  of dpkPatchPedestal, dpkStallPatch:
    result.iconKind = pciPatch
    result.patch = pickup.patch
    result.tag = patchKbLabel(pickup.patch) & " // " &
                 patchCategoryName(patchCategory(pickup.patch)).toUpperAscii()
    result.title = patchName(pickup.patch)
    result.body = patchDescription(pickup.patch)
    result.action = t("card_patch_action")
  of dpkStallPowerUp:
    let lvl = stallNextLevel(game, pickup)
    result.iconKind = pciPowerUp
    result.powerUp = pickup.powerUp.powerType
    result.accent = getPowerUpColor(pickup.powerUp.powerType)
    result.tag = t("card_tag_package")
    result.title = getPowerUpName(pickup.powerUp.powerType) &
                   (if lvl > 1: " " & t("roguelite_level") & $lvl else: "")
    result.body = if lvl > 0: getPowerUpDescription(pickup.powerUp.powerType, lvl, game.player.damage)
                  else: t("card_maxed_desc")
    result.action = t("card_install_action")
    result.disabled = lvl <= 0
  of dpkStallRepair:
    result.iconKind = pciReward
    result.reward = rrwRepair
    result.accent = rewardAccent(rrwRepair)
    result.tag = t("card_tag_repair")
    result.title = t("stall_repair_title")
    result.body = t("stall_repair_desc").replace("$1", $pickup.amount)
    result.action = t("card_buy_action")
  of dpkStallRestock:
    result.iconKind = pciReward
    result.reward = rrwShop
    result.accent = rewardAccent(rrwShop)
    result.tag = t("card_tag_restock")
    result.title = t("stall_restock_title")
    result.body = t("stall_restock_desc")
    result.action = t("card_buy_action")
  else:
    discard
  if isStall(pickup.kind):
    result.price = stallPrice(game, room, pickup)
    result.affordable = game.player.coins >= result.price and not result.disabled
    if not result.affordable and not result.disabled:
      result.action = noCreditsLabel()
  else:
    result.affordable = true

proc drawExitPortal(game: Game) =
  ## The swirling SERVICE-clear portal: a dark vortex with rotating accent
  ## spiral arms that scale into existence (spawn animation) then idle-pulse.
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
  ## Doors, pickups, the proximity card and the room-transition fade.
  ## Called from drawGame for roguelite mode (after entities, before HUD).
  let run = game.rogueliteRun
  if run.isNil or run.floor.isNil: return
  let floor = run.floor
  let room = currentDungeonRoom(run)
  if room.isNil: return

  # Doors: the way in (closed), and the ways out.
  if room.kind != drkStart:
    drawEntryDoor(game)
  let open = exitsOpen(room)
  let bossNumber = dungeonBossNumber(game)
  for ex in exitsOf(floor, room):
    drawExitDoor(game, ex, open, bossNumber)

  # A cleared folder whose reward is still waiting says so.
  if room.cleared and not room.rewardClaimed and room.rewardSpawned:
    let hint = t("dungeon_claim_hint")
    let hw = measureText(hint, 14)
    let a = uint8(170.0'f32 + 70.0'f32 * sin(game.time * 3.0'f32))
    drawText(hint, game.screenWidth div 2 - hw div 2, game.screenHeight div 2 + 70, 14,
             Color(r: 200, g: 225, b: 255, a: a))

  # Pickups.
  for i, pickup in room.pickups:
    if not pickup.taken:
      drawPickup(game, room, i, pickup)

  # SERVICE-clear exit portal (drawn under the card and the fade)
  if game.bossPortalActive and room.kind == drkBoss:
    drawExitPortal(game)

  # Proximity card for the pedestal/stall in [E] range.
  if focusedPickup >= 0 and focusedPickup < room.pickups.len and
     not room.pickups[focusedPickup].taken and not game.roomTransitionActive:
    let pickup = room.pickups[focusedPickup]
    drawProximityCard(pickupCard(game, room, pickup), pickup.pos.x, pickup.pos.y,
                      game.screenWidth, game.screenHeight, game.time)

  # Transition fade (dark at the midpoint)
  if game.roomTransitionActive:
    let half = RoomTransitionDuration / 2
    let p = game.roomTransitionTimer
    let alphaF = if p < half: p / half else: 1.0'f32 - (p - half) / half
    drawRectangle(0, 0, game.screenWidth, game.screenHeight,
                  Color(r: 0, g: 0, b: 0, a: uint8(clamp(alphaF, 0.0, 1.0) * 255)))
