## Mode boss rosters: the Survival phase bosses (13-15), the Roguelite folder
## guardians (17-22) and the Omega Entity re-armed with each mode's kit
## (16 = survival, 23 = roguelite).
##
## Same data model as the wave campaign in boss_definitions.nim; that module
## dispatches IDs 13..23 here. Each boss is authored for one slot on the wave
## boss curve (bossAuthoredSlotWave): the survival bosses stand in for bosses
## 3 / 6 / 9 / 12 at the same slots, so their numbers match those bosses; the
## guardians are written at the sector-1 budget and rescaled per sector by
## normalizeBossToSlot.
##
## Signature attacks are routed by specialData before the attackType dispatch
## (executeCustomBossAttack in game/bosses.nim). Their nominal attackType is
## bapMeteor so the generic pre-fire telegraph stays out of the way: each one
## draws its own warning. What each specialData means, and how it reads the
## BossAttack fields, is documented where it is spawned (ui/mode_warnings.nim
## and game/bosses.nim).
##
## BossAttack.timer is a start offset added to the first countdown (spawn and
## every phase change): it staggers fillers onto a beat grid.

import raylib
import boss_types, localization, types

proc atk(kind: BossAttackPattern, damage, cooldown: float32, speed = 0.0'f32,
         count = 0, spread = 0.0'f32, dur = 0.0'f32, special = "",
         radius = 0.0'f32, offset = 0.0'f32): BossAttack =
  BossAttack(attackType: kind, damage: damage, cooldown: cooldown,
             projectileSpeed: speed, projectileCount: count, spreadAngle: spread,
             durationOrRadius: dur, specialData: special, bulletRadius: radius,
             timer: offset)

proc phase(name: string, hp, speed, dmg, defense: float32, color: Color,
           fx, behavior: string, attacks: seq[BossAttack]): BossPhaseDefinition =
  BossPhaseDefinition(name: name, hpThreshold: hp, speedMultiplier: speed,
                      damageMultiplier: dmg, defenseMultiplier: defense,
                      color: color, visualEffect: fx, specialBehavior: behavior,
                      attacks: attacks)

proc col(r, g, b: int): Color {.inline.} =
  Color(r: r.uint8, g: g.uint8, b: b.uint8, a: 255)

# ---------------------------------------------------------------------------
# SURVIVAL: the flood's spawn. Each boss plays WITH the horde.

proc forkmother(): BossDefinition =
  ## Boot phase (slot 15, stands in for boss 3). Her children are Royal-Guard
  ## style objectives hidden in the horde: while any lives her body is sealed,
  ## the last one down opens the window. Signature: Exponential Fork, seeds
  ## that double every beat unless shot first.
  BossDefinition(
    name: t(tkBoss13Name), bossID: BossForkmother, description: t(tkBoss13Desc),
    baseHP: 400.0, baseSpeed: 60.0, baseDamage: 2, baseRadius: 48.0,
    color: col(255, 90, 170),
    phases: @[
      phase(t(tkBoss13Phase1), 1.0, 1.0, 1.0, 0.9, col(255, 90, 170), "pulse", "defensive", @[
        # children: projectileCount = how many, durationOrRadius = raise ring radius
        atk(bapSummon, 2.0, 9.0, count = 2, dur = 110.0, special = "fork_children"),
        # seeds: projectileCount = splits (depth), spreadAngle = branch angle (deg),
        # durationOrRadius = beat between splits, projectileSpeed = flight speed
        atk(bapMeteor, 2.0, 7.0, speed = 150.0, count = 2, spread = 34.0, dur = 0.85,
            special = "exponential_fork", offset = 2.0),
        atk(bapCircle, 2.0, 3.4, speed = 150.0, count = 12, special = "fork_ring")]),
      phase(t(tkBoss13Phase2), 0.55, 1.05, 1.1, 1.0, col(255, 60, 200), "aura", "circle_movement", @[
        atk(bapSummon, 2.0, 10.0, count = 3, dur = 120.0, special = "fork_children"),
        atk(bapMeteor, 2.0, 7.5, speed = 155.0, count = 3, spread = 30.0, dur = 0.8,
            special = "exponential_fork", offset = 2.5),
        atk(bapCircle, 2.0, 3.2, speed = 155.0, count = 14, special = "fork_ring"),
        atk(bapTargeted, 2.0, 2.4, speed = 190.0, count = 3, spread = 18.0)]),
      phase(t(tkBoss13Phase3), 0.25, 1.1, 1.2, 1.1, col(255, 40, 140), "glow", "adaptive_combat", @[
        atk(bapSummon, 2.0, 9.0, count = 3, dur = 120.0, special = "fork_children"),
        atk(bapMeteor, 2.0, 8.0, speed = 160.0, count = 3, spread = 30.0, dur = 0.75,
            special = "exponential_fork_twin", offset = 2.0),
        atk(bapCircle, 2.0, 3.0, speed = 160.0, count = 16, special = "fork_ring")])])

proc dispatcher(): BossDefinition =
  ## Runtime phase (slot 30, stands in for boss 6). Signature: Marching
  ## Orders, ranks of REAL killable bodies march across the arena as a wall;
  ## the player shoots their own gap. Priority Boost hastes the horde.
  BossDefinition(
    name: t(tkBoss14Name), bossID: BossDispatcher, description: t(tkBoss14Desc),
    baseHP: 1250.0, baseSpeed: 55.0, baseDamage: 3, baseRadius: 55.0,
    color: col(255, 170, 40),
    phases: @[
      phase(t(tkBoss14Phase1), 1.0, 1.0, 1.0, 0.95, col(255, 170, 40), "pulse", "defensive", @[
        # ranks: projectileCount = ranks, durationOrRadius = bodies per rank,
        # projectileSpeed = march speed, damage = contact damage per body
        atk(bapMeteor, 8.0, 9.0, speed = 115.0, count = 1, dur = 13.0,
            special = "marching_orders", offset = 1.5),
        atk(bapTargeted, 8.0, 2.4, speed = 200.0, count = 3, spread = 18.0),
        atk(bapWave, 8.0, 4.5, speed = 170.0, count = 7, spread = 60.0)]),
      phase(t(tkBoss14Phase2), 0.6, 1.05, 1.1, 1.0, col(255, 140, 20), "aura", "circle_movement", @[
        atk(bapMeteor, 8.0, 10.0, speed = 120.0, count = 2, dur = 13.0,
            special = "marching_orders", offset = 1.5),
        # boost: durationOrRadius = radius, spreadAngle = haste fraction
        atk(bapPulse, 0.0, 8.0, spread = 0.35, dur = 330.0, special = "priority_boost", offset = 4.0),
        atk(bapTargeted, 8.0, 2.4, speed = 205.0, count = 3, spread = 18.0)]),
      phase(t(tkBoss14Phase3), 0.3, 1.1, 1.2, 1.1, col(255, 100, 0), "glow", "adaptive_combat", @[
        atk(bapMeteor, 8.0, 11.0, speed = 125.0, count = 3, dur = 12.0,
            special = "marching_orders", offset = 1.5),
        atk(bapPulse, 0.0, 7.0, spread = 0.4, dur = 360.0, special = "priority_boost", offset = 3.0),
        atk(bapWave, 8.0, 4.0, speed = 175.0, count = 9, spread = 70.0)])])

proc thermalRunaway(): BossDefinition =
  ## Overload phase (slot 45, stands in for boss 9). Signature: Heat Trail,
  ## the player's own footsteps arm into burning ground (it burns the horde
  ## too, so lead them through it). Thermal Vents erupt under the densest
  ## crowds.
  BossDefinition(
    name: t(tkBoss15Name), bossID: BossThermalRunaway, description: t(tkBoss15Desc),
    baseHP: 2500.0, baseSpeed: 55.0, baseDamage: 4, baseRadius: 56.0,
    color: col(255, 90, 30),
    phases: @[
      phase(t(tkBoss15Phase1), 1.0, 1.0, 1.0, 1.05, col(255, 90, 30), "pulse", "balanced_assault", @[
        # trail: durationOrRadius = seconds the emitter tracks the player,
        # bulletRadius = trail node radius, damage = per touch
        atk(bapMeteor, 16.0, 11.0, dur = 5.0, radius = 16.0, special = "heat_trail", offset = 1.0),
        atk(bapCircle, 16.0, 3.5, speed = 160.0, count = 14),
        atk(bapTargeted, 16.0, 2.8, speed = 210.0, count = 3, spread = 16.0)]),
      phase(t(tkBoss15Phase2), 0.67, 1.05, 1.1, 1.1, col(255, 60, 10), "aura", "aggressive_mixed", @[
        atk(bapMeteor, 16.0, 11.0, dur = 6.0, radius = 17.0, special = "heat_trail", offset = 1.0),
        # vents: projectileCount = vents, durationOrRadius = vent radius
        atk(bapMeteor, 16.0, 6.5, count = 3, dur = 80.0, special = "thermal_vents", offset = 3.5),
        atk(bapCircle, 16.0, 3.4, speed = 165.0, count = 16)]),
      phase(t(tkBoss15Phase3), 0.33, 1.1, 1.2, 1.15, col(255, 30, 0), "glow", "adaptive_combat", @[
        atk(bapMeteor, 16.0, 10.0, dur = 7.0, radius = 18.0, special = "heat_trail", offset = 1.0),
        atk(bapMeteor, 16.0, 5.5, count = 4, dur = 90.0, special = "thermal_vents", offset = 3.0),
        atk(bapPulse, 16.0, 5.0, speed = 220.0, dur = 260.0),
        atk(bapTargeted, 16.0, 2.8, speed = 215.0, count = 3, spread = 16.0)])])

proc omegaSurvival(): BossDefinition =
  ## Kernel Panic (slot 60). The Omega Entity with the survival kit: Alpha,
  ## Beta and Gamma echo the three flood bosses in order, and the Omega phase
  ## floods the arena until only a drifting Safe Mode bubble is left.
  BossDefinition(
    name: t(tkBoss12Name), bossID: BossOmegaSurvival, description: t(tkBoss16Desc),
    baseHP: 4000.0, baseSpeed: 60.0, baseDamage: 6, baseRadius: 70.0,
    color: col(255, 50, 50),
    phases: @[
      phase(t(tkBoss16Phase1), 1.0, 0.9, 0.9, 1.55, col(255, 50, 50), "shield", "balanced_assault", @[
        atk(bapSummon, 26.0, 10.0, count = 3, dur = 130.0, special = "fork_children"),
        atk(bapMeteor, 26.0, 7.5, speed = 165.0, count = 3, spread = 30.0, dur = 0.8,
            special = "exponential_fork", offset = 2.5),
        atk(bapCircle, 26.0, 3.0, speed = 170.0, count = 18, special = "fork_ring")]),
      phase(t(tkBoss16Phase2), 0.7, 1.1, 1.15, 1.45, col(255, 100, 0), "aura", "aggressive_mixed", @[
        atk(bapMeteor, 26.0, 9.5, speed = 135.0, count = 2, dur = 14.0,
            special = "marching_orders", offset = 1.5),
        atk(bapPulse, 0.0, 8.0, spread = 0.35, dur = 360.0, special = "priority_boost", offset = 4.0),
        atk(bapTargeted, 26.0, 2.6, speed = 215.0, count = 3, spread = 18.0)]),
      phase(t(tkBoss16Phase3), 0.5, 1.15, 1.25, 1.325, col(255, 255, 0), "pulse", "adaptive_combat", @[
        atk(bapMeteor, 29.0, 10.0, dur = 6.0, radius = 18.0, special = "heat_trail", offset = 1.0),
        atk(bapMeteor, 29.0, 6.0, count = 4, dur = 90.0, special = "thermal_vents", offset = 3.5),
        atk(bapCircle, 26.0, 4.0, speed = 175.0, count = 18, special = "fork_ring")]),
      # THE BEAT GRID: fillers land on multiples of 2.4 s (2.4 / 4.8), and the
      # Safe Mode cast is a mega-cast that pauses them while it runs.
      phase(t(tkBoss16Phase4), 0.2, 1.2, 1.5, 3.0, col(255, 0, 255), "glow", "final_form", @[
        # safe mode: durationOrRadius = cast seconds, projectileSpeed = bubble
        # drift speed, damage = per flood tick
        atk(bapMeteor, 14.0, 15.0, speed = 70.0, dur = 9.0, special = "safe_mode", offset = 1.0),
        # payload: projectileCount = orbs, each hatches a Thread where it stops
        atk(bapCircle, 26.0, 4.8, speed = 190.0, count = 8, special = "payload_ring", offset = 2.4),
        atk(bapCircle, 26.0, 2.4, speed = 190.0, count = 16, special = "fork_ring")])])

# ---------------------------------------------------------------------------
# ROGUELITE: legacy processes, older than TOPHAT. Each guardian is fought in a
# folder room and uses it: cover, walls, the floor itself.

proc gatekeeper(): BossDefinition =
  ## Firewall guardian. Signature: Stateful Inspection, rotating searchlight
  ## beams that the room's obstacles block. Anchored at the room's centre.
  BossDefinition(
    name: t(tkBoss17Name), bossID: BossGatekeeper, description: t(tkBoss17Desc),
    baseHP: 165.0, baseSpeed: 40.0, baseDamage: 1, baseRadius: 50.0,
    color: col(255, 110, 48),
    phases: @[
      phase(t(tkBoss17Phase1), 1.0, 1.0, 1.0, 0.85, col(255, 110, 48), "pulse", "anchored", @[
        # inspection: projectileCount = beams, durationOrRadius = sweep seconds,
        # projectileSpeed = angular speed (rad/s)
        atk(bapMeteor, 1.5, 9.0, speed = 0.55, count = 1, dur = 5.0,
            special = "stateful_inspection", offset = 1.5),
        atk(bapTargeted, 1.0, 2.0, speed = 180.0, count = 3, spread = 14.0)]),
      phase(t(tkBoss17Phase2), 0.6, 1.0, 1.1, 0.95, col(255, 80, 30), "aura", "anchored", @[
        atk(bapMeteor, 1.5, 9.0, speed = 0.6, count = 2, dur = 5.5,
            special = "stateful_inspection", offset = 1.5),
        # guards: projectileCount = Port Guards raised at the gate
        atk(bapSummon, 1.0, 12.0, count = 2, dur = 90.0, special = "port_guards", offset = 4.0),
        atk(bapTargeted, 1.0, 2.2, speed = 185.0, count = 3, spread = 14.0)]),
      phase(t(tkBoss17Phase3), 0.3, 1.0, 1.2, 1.05, col(255, 50, 20), "glow", "anchored", @[
        atk(bapMeteor, 1.5, 8.0, speed = 0.75, count = 2, dur = 6.0,
            special = "stateful_inspection", offset = 1.0),
        atk(bapWave, 1.0, 3.5, speed = 170.0, count = 7, spread = 70.0),
        atk(bapTargeted, 1.0, 2.0, speed = 190.0, count = 3, spread = 14.0)])])

proc compactor(): BossDefinition =
  ## Recycle Bin guardian. Signature: Empty Trash, dormant file bombs strewn
  ## around the room all burst together later; walk over or shoot them first.
  ## Undelete: a restore point that rolls its HP back unless broken in time.
  BossDefinition(
    name: t(tkBoss18Name), bossID: BossCompactor, description: t(tkBoss18Desc),
    baseHP: 160.0, baseSpeed: 45.0, baseDamage: 1, baseRadius: 50.0,
    color: col(150, 190, 140),
    phases: @[
      phase(t(tkBoss18Phase1), 1.0, 1.0, 1.0, 0.85, col(150, 190, 140), "pulse", "defensive", @[
        # trash: projectileCount = bombs, durationOrRadius = fuse to the purge,
        # projectileSpeed = shrapnel speed
        atk(bapMeteor, 1.5, 11.0, speed = 150.0, count = 5, dur = 5.0,
            special = "empty_trash", offset = 1.5),
        atk(bapBurst, 1.0, 2.2, speed = 190.0, count = 4, spread = 20.0)]),
      phase(t(tkBoss18Phase2), 0.6, 1.05, 1.1, 0.95, col(120, 210, 110), "aura", "circle_movement", @[
        atk(bapMeteor, 1.5, 11.0, speed = 155.0, count = 6, dur = 5.0,
            special = "empty_trash", offset = 1.5),
        # restore point: durationOrRadius = window, spreadAngle = share of the
        # phase pool that breaks it
        atk(bapMeteor, 0.0, 14.0, spread = 0.12, dur = 6.0, special = "undelete", offset = 6.0),
        atk(bapBurst, 1.0, 2.2, speed = 195.0, count = 4, spread = 20.0)]),
      phase(t(tkBoss18Phase3), 0.3, 1.1, 1.2, 1.05, col(90, 230, 80), "glow", "aggressive_mixed", @[
        atk(bapMeteor, 1.5, 10.0, speed = 160.0, count = 8, dur = 5.5,
            special = "empty_trash", offset = 1.0),
        atk(bapMeteor, 0.0, 13.0, spread = 0.12, dur = 6.0, special = "undelete", offset = 5.0),
        atk(bapCircle, 1.0, 3.6, speed = 150.0, count = 12)])])

proc hive(): BossDefinition =
  ## Registry guardian. Signature: Audit Lock, the whole room freezes and any
  ## movement or shot during the audit is a write, and gets punished.
  BossDefinition(
    name: t(tkBoss19Name), bossID: BossHive, description: t(tkBoss19Desc),
    baseHP: 150.0, baseSpeed: 45.0, baseDamage: 1, baseRadius: 48.0,
    color: col(90, 160, 255),
    phases: @[
      phase(t(tkBoss19Phase1), 1.0, 1.0, 1.0, 0.85, col(90, 160, 255), "pulse", "geometric_movement", @[
        # audit: durationOrRadius = locked window (the telegraph is fixed)
        atk(bapMeteor, 2.0, 12.0, dur = 1.2, special = "audit_lock", offset = 3.0),
        atk(bapSpiral, 1.0, 1.4, speed = 150.0, count = 5, spread = 45.0, dur = 1.5),
        atk(bapTargeted, 1.0, 2.6, speed = 185.0, count = 2, spread = 12.0)]),
      phase(t(tkBoss19Phase2), 0.6, 1.05, 1.1, 0.95, col(60, 120, 255), "aura", "geometric_movement", @[
        atk(bapMeteor, 2.0, 11.0, dur = 1.4, special = "audit_lock", offset = 2.5),
        atk(bapSpiral, 1.0, 1.3, speed = 155.0, count = 6, spread = 40.0, dur = 1.6),
        atk(bapTargeted, 1.0, 2.4, speed = 190.0, count = 3, spread = 14.0)]),
      phase(t(tkBoss19Phase3), 0.3, 1.1, 1.2, 1.05, col(40, 80, 255), "glow", "adaptive_combat", @[
        atk(bapMeteor, 2.0, 9.5, dur = 1.5, special = "audit_lock", offset = 2.0),
        atk(bapSpiral, 1.0, 1.2, speed = 160.0, count = 7, spread = 40.0, dur = 1.8),
        atk(bapWave, 1.0, 4.0, speed = 170.0, count = 7, spread = 60.0)])])

proc router(): BossDefinition =
  ## Network guardian. Signature: Packet Switching, lit links across the room
  ## carry trains of packets; cross the lanes between trains.
  BossDefinition(
    name: t(tkBoss20Name), bossID: BossRouter, description: t(tkBoss20Desc),
    baseHP: 150.0, baseSpeed: 50.0, baseDamage: 1, baseRadius: 48.0,
    color: col(0, 220, 255),
    phases: @[
      phase(t(tkBoss20Phase1), 1.0, 1.0, 1.0, 0.85, col(0, 220, 255), "pulse", "circle_movement", @[
        # links: projectileCount = links, projectileSpeed = packet speed,
        # durationOrRadius = link telegraph
        atk(bapMeteor, 1.5, 8.0, speed = 320.0, count = 3, dur = 1.2,
            special = "packet_switching", offset = 1.5),
        atk(bapPulse, 1.0, 5.0, speed = 180.0, dur = 240.0),
        atk(bapTargeted, 1.0, 2.4, speed = 190.0, count = 2, spread = 12.0)]),
      phase(t(tkBoss20Phase2), 0.6, 1.05, 1.1, 0.95, col(0, 180, 255), "aura", "circle_movement", @[
        atk(bapMeteor, 1.5, 7.5, speed = 350.0, count = 4, dur = 1.15,
            special = "packet_switching", offset = 1.5),
        atk(bapPulse, 1.0, 5.0, speed = 190.0, dur = 250.0),
        atk(bapTargeted, 1.0, 2.4, speed = 195.0, count = 3, spread = 14.0)]),
      phase(t(tkBoss20Phase3), 0.3, 1.1, 1.2, 1.05, col(0, 140, 255), "glow", "adaptive_combat", @[
        atk(bapMeteor, 1.5, 7.0, speed = 370.0, count = 5, dur = 1.1,
            special = "packet_switching", offset = 1.0),
        atk(bapPulse, 1.0, 4.6, speed = 200.0, dur = 260.0),
        atk(bapTargeted, 1.0, 2.2, speed = 200.0, count = 3, spread = 14.0)])])

proc supervisor(): BossDefinition =
  ## Kernel guardian. Signature: Page Fault, the room's obstacles page out and
  ## page back in elsewhere; standing in a ghost footprint gets you crushed.
  BossDefinition(
    name: t(tkBoss21Name), bossID: BossSupervisor, description: t(tkBoss21Desc),
    baseHP: 170.0, baseSpeed: 45.0, baseDamage: 1, baseRadius: 52.0,
    color: col(150, 95, 235),
    phases: @[
      phase(t(tkBoss21Phase1), 1.0, 1.0, 1.0, 0.85, col(150, 95, 235), "pulse", "balanced_assault", @[
        # page fault: projectileCount = obstacles paged, durationOrRadius =
        # ghost footprint telegraph
        atk(bapMeteor, 2.0, 10.0, count = 2, dur = 1.6, special = "page_fault", offset = 2.0),
        atk(bapWave, 1.0, 3.5, speed = 170.0, count = 7, spread = 70.0)]),
      phase(t(tkBoss21Phase2), 0.6, 1.05, 1.1, 0.95, col(130, 70, 245), "aura", "balanced_assault", @[
        atk(bapMeteor, 2.0, 9.0, count = 3, dur = 1.5, special = "page_fault", offset = 2.0),
        atk(bapWave, 1.0, 3.5, speed = 175.0, count = 7, spread = 70.0),
        atk(bapTargeted, 1.0, 2.6, speed = 190.0, count = 2, spread = 12.0)]),
      phase(t(tkBoss21Phase3), 0.3, 1.1, 1.2, 1.05, col(110, 40, 255), "glow", "adaptive_combat", @[
        atk(bapMeteor, 2.0, 8.0, count = 4, dur = 1.4, special = "page_fault", offset = 1.5),
        atk(bapCircle, 1.0, 3.6, speed = 155.0, count = 12),
        atk(bapTargeted, 1.0, 2.4, speed = 195.0, count = 3, spread = 14.0)])])

proc mirrorCache(): BossDefinition =
  ## Cache guardian. Signature: Stale Copy, a hostile echo that replays the
  ## player's movement and shots from a few seconds ago.
  BossDefinition(
    name: t(tkBoss22Name), bossID: BossMirrorCache, description: t(tkBoss22Desc),
    baseHP: 150.0, baseSpeed: 50.0, baseDamage: 1, baseRadius: 48.0,
    color: col(70, 215, 195),
    phases: @[
      phase(t(tkBoss22Phase1), 1.0, 1.0, 1.0, 0.85, col(70, 215, 195), "pulse", "circle_player", @[
        # echo: projectileCount = echoes, durationOrRadius = echo lifetime,
        # spreadAngle = replay delay (seconds)
        atk(bapMeteor, 1.5, 12.0, count = 1, spread = 3.0, dur = 7.0,
            special = "stale_copy", offset = 2.0),
        atk(bapBurst, 1.0, 2.4, speed = 190.0, count = 4, spread = 20.0)]),
      phase(t(tkBoss22Phase2), 0.6, 1.05, 1.1, 0.95, col(40, 230, 200), "aura", "circle_player", @[
        atk(bapMeteor, 1.5, 11.0, count = 1, spread = 2.6, dur = 8.0,
            special = "stale_copy", offset = 2.0),
        atk(bapBurst, 1.0, 2.4, speed = 195.0, count = 4, spread = 20.0),
        atk(bapCircle, 1.0, 4.2, speed = 150.0, count = 12)]),
      phase(t(tkBoss22Phase3), 0.3, 1.1, 1.2, 1.05, col(20, 255, 210), "glow", "adaptive_combat", @[
        atk(bapMeteor, 1.5, 11.0, count = 2, spread = 3.0, dur = 8.0,
            special = "stale_copy", offset = 1.5),
        atk(bapBurst, 1.0, 2.2, speed = 200.0, count = 5, spread = 24.0)])])

proc omegaRoguelite(): BossDefinition =
  ## Final sector (slot 60, normalized to the sector like every SERVICE). The
  ## Omega Entity with the roguelite kit: Alpha, Beta and Gamma echo two
  ## guardians each, and the Omega phase is Last Known Good, one real door
  ## among decoys while the room is purged from the centre out.
  BossDefinition(
    name: t(tkBoss12Name), bossID: BossOmegaRoguelite, description: t(tkBoss23Desc),
    baseHP: 4000.0, baseSpeed: 60.0, baseDamage: 6, baseRadius: 70.0,
    color: col(255, 50, 50),
    phases: @[
      phase(t(tkBoss23Phase1), 1.0, 0.9, 0.9, 1.55, col(255, 50, 50), "shield", "balanced_assault", @[
        atk(bapMeteor, 30.0, 9.0, speed = 0.6, count = 2, dur = 5.0,
            special = "stateful_inspection", offset = 1.5),
        atk(bapMeteor, 28.0, 11.0, speed = 160.0, count = 6, dur = 5.0,
            special = "empty_trash", offset = 5.0),
        atk(bapTargeted, 26.0, 2.5, speed = 200.0, count = 3, spread = 16.0)]),
      phase(t(tkBoss23Phase2), 0.7, 1.1, 1.15, 1.45, col(255, 100, 0), "aura", "aggressive_mixed", @[
        atk(bapMeteor, 30.0, 12.0, dur = 1.3, special = "audit_lock", offset = 3.0),
        atk(bapMeteor, 28.0, 8.0, speed = 380.0, count = 4, dur = 1.15,
            special = "packet_switching", offset = 6.5),
        atk(bapSpiral, 26.0, 1.6, speed = 160.0, count = 6, spread = 40.0, dur = 1.6)]),
      phase(t(tkBoss23Phase3), 0.5, 1.15, 1.25, 1.325, col(255, 255, 0), "pulse", "adaptive_combat", @[
        atk(bapMeteor, 30.0, 9.0, count = 3, dur = 1.5, special = "page_fault", offset = 2.0),
        atk(bapMeteor, 28.0, 11.0, count = 1, spread = 3.0, dur = 7.0,
            special = "stale_copy", offset = 5.5),
        atk(bapBurst, 26.0, 2.6, speed = 200.0, count = 4, spread = 20.0)]),
      # THE BEAT GRID again (2.4 / 4.8 / 7.2); Last Known Good is a mega-cast.
      phase(t(tkBoss23Phase4), 0.2, 1.2, 1.5, 3.0, col(255, 0, 255), "glow", "final_form", @[
        # doors: durationOrRadius = seconds to reach the real door
        atk(bapMeteor, 38.0, 14.0, dur = 4.2, special = "last_known_good", offset = 1.0),
        atk(bapTargeted, 26.0, 2.4, speed = 210.0, count = 3, spread = 16.0),
        atk(bapMeteor, 26.0, 4.8, speed = 400.0, count = 3, dur = 1.0,
            special = "packet_switching", offset = 2.4),
        atk(bapCircle, 26.0, 7.2, speed = 170.0, count = 14, offset = 3.6)])])

proc getModeBossDefinition*(bossNumber: int): BossDefinition =
  ## Definitions for boss IDs 13..23 (weak points are filled in by the caller).
  case bossNumber
  of BossForkmother: forkmother()
  of BossDispatcher: dispatcher()
  of BossThermalRunaway: thermalRunaway()
  of BossOmegaSurvival: omegaSurvival()
  of BossGatekeeper: gatekeeper()
  of BossCompactor: compactor()
  of BossHive: hive()
  of BossRouter: router()
  of BossSupervisor: supervisor()
  of BossMirrorCache: mirrorCache()
  of BossOmegaRoguelite: omegaRoguelite()
  else: omegaSurvival()
