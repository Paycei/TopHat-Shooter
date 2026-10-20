## Binds every {.moddable.} proc of the game to the mixin runtime (see
## mod_mixin_bind). main.nim imports this module last, so every module with
## moddable procs has been compiled when the binders run; one compiled after
## it would be missed, which the debug self-check reports. The binding is
## split over a module per group (their C compiles in parallel); the order of
## the imports matters only in that a group binds what the earlier ones left
## (mod_mixin_windows takes every src/ui/ module mod_mixin_hud did not).

{.used.}   # imported for what it generates
import mod_mixin_bind
import mod_mixin_combat, mod_mixin_world, mod_mixin_modes, mod_mixin_meta, mod_mixin_hud, mod_mixin_windows

bindModdables(currentSourcePath())   # the rest (effects, skins, main.nim's own imports...)

proc unboundModdables*(): seq[string] =
  ## Debug self-check: moddable procs no binder generated the mixin code for.
  let bound = boundModdableNames()
  for n in moddableNames:
    if n notin bound: result.add("moddable proc not bound to mixins: " & n)
