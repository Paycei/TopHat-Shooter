## engine.call for every exported proc of the game's own modules that is not
## {.moddable.} (the moddable ones are bound, mixins included, by
## mod_mixin_game). Helpers, drawing primitives, the save system...: callable
## from scripts, not wrappable. The UI's modules are in mod_engine_ui (their
## generated code compiles in parallel with this one's).
##
## Left out on purpose: main.nim (not a module), the Discord client
## (discord_*: a worker thread and a pipe) and network/ (sockets; PvP is
## scripted through match and the pvp* hooks).
## A new module of the game goes in this list (or mod_engine_ui's).

{.used.}   # imported for what it generates
import mod_mixin_bind

bindCallables(currentSourcePath(), [
  "../advancement.nim", "../boss_definitions.nim", "../boss_weakpoints.nim", "../bullet.nim",
  "../bullet_shapes.nim", "../bullet_skins.nim", "../cheat.nim", "../coin.nim", "../consumable.nim",
  "../cube_render.nim", "../cube_skins.nim", "../d_enhancements.nim", "../d_systems.nim",
  "../d_visuals.nim", "../desktop_bg_skins.nim", "../draw_prims.nim", "../dungeon.nim",
  "../effects.nim", "../enemy.nim", "../enemy_config.nim", "../enemy_helpers.nim", "../feedback.nim",
  "../fx.nim", "../game.nim", "../gamemode_definitions.nim", "../gamepad_input.nim",
  "../hardware_info.nim", "../input_intent.nim", "../localization.nim", "../mode_enemies.nim", "../mode_hazards.nim",
  "../mode_visuals.nim", "../particle.nim", "../particle_pool.nim", "../particle_skins.nim",
  "../particle_types.nim", "../patches.nim", "../pickup.nim", "../player.nim", "../post_fx.nim", "../powerup.nim",
  "../powerup_data.nim", "../pvp_game.nim", "../render_context.nim", "../roguelite.nim",
  "../run_save.nim", "../run_statistics.nim", "../sandbox.nim", "../save_system.nim",
  "../settings.nim", "../shapes.nim", "../skins.nim", "../sound.nim", "../statistics.nim",
  "../survival.nim", "../suspend.nim", "../tutorial.nim", "../types.nim", "../utils.nim", "../vec.nim",
  "../wall.nim", "../xp_orb.nim",
  "../game/abilities.nim", "../game/auras.nim", "../game/bosses.nim", "../game/bullets.nim", "../game/combat.nim",
  "../game/death.nim", "../game/mode_boss_attacks.nim", "../game/mode_mechanics.nim",
  "../game/orbitals.nim", "../game/shooting.nim", "../game/things.nim",
  "../game3d/boss_3d.nim", "../game3d/engine_3d.nim", "../game3d/game_3d.nim",
  "../game3d/player_3d.nim", "../game3d/types_3d.nim"])
