## Binds the {.moddable.} procs of the run itself: game.nim, the player,
## enemies, bullets, power-ups, bosses and pickups to the mixin runtime (see
## mod_mixin_bind). One of the binder modules mod_mixin_game imports: the
## binding is split so its C compiles in parallel.

{.used.}   # imported for what it generates
import mod_mixin_bind

bindModdablesIn(currentSourcePath(), [
  "../game.nim",
  "../player.nim",
  "../input_intent.nim",
  "../enemy.nim",
  "../enemy_config.nim",
  "../enemy_helpers.nim",
  "../bullet.nim",
  "../bullet_shapes.nim",
  "../powerup.nim",
  "../powerup_data.nim",
  "../boss_definitions.nim",
  "../boss_weakpoints.nim",
  "../mode_enemies.nim",
  "../mode_hazards.nim",
  "../mode_visuals.nim",
  "../wall.nim",
  "../xp_orb.nim",
  "../coin.nim",
  "../consumable.nim",
  "../pickup.nim"])
