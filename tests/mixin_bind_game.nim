## test_mod_lua's binder: binds the game's {.moddable.} procs that test
## imported before this module. A module of its own because the binder
## imports every module it binds into the calling scope (in test_mod_lua,
## pvp_game's modBanner proc would hide mod_registry's modBanner).

{.used.}   # imported for what it generates
import ../src/modding/mod_mixin_bind

bindModdables(currentSourcePath())
