## Binds the {.moddable.} procs of the desktop, the window manager and every
## window of src/ui/ to the mixin runtime (see mod_mixin_bind). One of the
## binder modules mod_mixin_game imports: the binding is split so its C compiles
## in parallel.

{.used.}   # imported for what it generates
import mod_mixin_bind

bindModdablesIn(currentSourcePath(), [
  "../ui/"])
