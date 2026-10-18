## Binds the {.moddable.} procs of progression and the systems around a run:
## saves, stats, advancements, settings, sound, text to the mixin runtime (see
## mod_mixin_bind). One of the binder modules mod_mixin_game imports: the
## binding is split so its C compiles in parallel.

{.used.}   # imported for what it generates
import mod_mixin_bind

bindModdablesIn(currentSourcePath(), [
  "../run_statistics.nim",
  "../advancement.nim",
  "../save_system.nim",
  "../run_save.nim",
  "../statistics.nim",
  "../settings.nim",
  "../suspend.nim",
  "../localization.nim",
  "../sound.nim",
  "../types.nim"])
