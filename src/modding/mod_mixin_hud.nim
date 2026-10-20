## Binds the {.moddable.} procs of the in-run interface, the cinematics and the
## drawing helpers of src/ui/ to the mixin runtime (see mod_mixin_bind). One of
## the binder modules mod_mixin_game imports: the binding is split so its C
## compiles in parallel.

{.used.}   # imported for what it generates
import mod_mixin_bind

bindModdablesIn(currentSourcePath(), [
  "../ui/cinematic_common.nim",
  "../ui/cutscene.nim",
  "../ui/endgame_cinematic.nim",
  "../ui/lore_cinematic.nim",
  "../ui/roguelite_end_cinematic.nim",
  "../ui/survival_end_cinematic.nim",
  "../ui/mode_intros.nim",
  "../ui/loading_screen.nim",
  "../ui/os_splash.nim",
  "../ui/os_system_screens.nim",
  "../ui/background_fx.nim",
  "../ui/desktop_bg_fx.nim",
  "../ui/os_background.nim",
  "../ui/icon_drawing.nim",
  "../ui/ui_theme.nim",
  "../ui/ui_helpers.nim",
  "../ui/hud_dock.nim",
  "../ui/os_combined_hud.nim",
  "../ui/os_legacy_hud.nim",
  "../ui/os_enemy_labels.nim",
  "../ui/os_debug_panel.nim",
  "../ui/warnings.nim",
  "../ui/tutorial_overlay.nim"])
