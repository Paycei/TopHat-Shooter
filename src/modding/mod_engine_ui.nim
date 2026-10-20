## engine.call for every exported proc of the game's UI (the OS desktop, its
## windows, the HUD, the cinematics) that is not {.moddable.}. See
## mod_engine_game for the rest of the game.

{.used.}   # imported for what it generates
import mod_mixin_bind

bindCallables(currentSourcePath(), [
  "../ui/advancements_window.nim", "../ui/background_fx.nim", "../ui/changelog_window.nim",
  "../ui/cinematic_common.nim", "../ui/credits_window.nim", "../ui/cutscene.nim",
  "../ui/desktop_bg_fx.nim", "../ui/endgame_cinematic.nim", "../ui/feedback_window.nim",
  "../ui/help_window.nim", "../ui/hud_dock.nim", "../ui/icon_drawing.nim",
  "../ui/language_select.nim", "../ui/loading_screen.nim", "../ui/lore_cinematic.nim",
  "../ui/mod_app_window.nim", "../ui/mode_intros.nim", "../ui/mods_window.nim",
  "../ui/os_background.nim", "../ui/os_combined_hud.nim", "../ui/os_debug_panel.nim",
  "../ui/os_desktop.nim", "../ui/os_enemy_labels.nim", "../ui/os_legacy_hud.nim",
  "../ui/os_powerup_installer.nim", "../ui/os_roguelite.nim", "../ui/os_shop.nim",
  "../ui/os_splash.nim", "../ui/os_system_screens.nim", "../ui/os_task_manager.nim",
  "../ui/os_window.nim", "../ui/profile_select.nim", "../ui/pvp_window.nim",
  "../ui/roguelite_end_cinematic.nim", "../ui/roguelite_window.nim", "../ui/sandbox_window.nim",
  "../ui/settings_window.nim", "../ui/shop_window.nim", "../ui/stats_window.nim",
  "../ui/survival_end_cinematic.nim", "../ui/tutorial_overlay.nim", "../ui/ui_helpers.nim",
  "../ui/ui_theme.nim", "../ui/warnings.nim", "../ui/window_manager.nim"])
