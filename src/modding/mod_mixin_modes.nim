## Binds the {.moddable.} procs of the game modes: survival, roguelite, PvP,
## sandbox, tutorial, cheats to the mixin runtime (see mod_mixin_bind). One of
## the binder modules mod_mixin_game imports: the binding is split so its C
## compiles in parallel.

{.used.}   # imported for what it generates
import mod_mixin_bind

bindModdablesIn(currentSourcePath(), [
  "../survival.nim",
  "../dungeon.nim",
  "../roguelite.nim",
  "../patches.nim",
  "../pvp_game.nim",
  "../sandbox.nim",
  "../tutorial.nim",
  "../gamemode_definitions.nim",
  "../cheat.nim"])
