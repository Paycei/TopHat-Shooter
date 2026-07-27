## Language and localization system for TopHat-ShooterOS
import std/tables

type
  Language* = enum
    English = "english"
    Spanish = "spanish"

  TranslationKey* = enum
    # Main Menu
    tkMenuPlay = "menu_play"
    tkMenuSurvival = "menu_survival"
    tkMenuStats = "menu_stats"
    tkMenuHelp = "menu_help"
    tkMenuSettings = "menu_settings"
    tkMenuQuit = "menu_quit"
    tkMenuSandbox = "menu_sandbox"

    # Desktop icons
    tkDesktopIconPlay = "desktop_icon_play"
    tkDesktopIconSurvival = "desktop_icon_survival"
    tkDesktopIconStats = "desktop_icon_stats"
    tkDesktopIconSettings = "desktop_icon_settings"
    tkDesktopIconHelp = "desktop_icon_help"
    tkDesktopIconQuit = "desktop_icon_quit"
    tkDesktopIconSandbox = "desktop_icon_sandbox"
    tkDesktopIconShop = "desktop_icon_shop"
    tkDesktopIconPvP = "desktop_icon_pvp"
    tkDesktopIconRoguelite = "desktop_icon_roguelite"
    tkDesktopIconAdvancements = "desktop_icon_advancements"
    tkDesktopIconChangelog = "desktop_icon_changelog"
    tkDesktopIconCredits = "desktop_icon_credits"

    # Credits window
    tkCreditsWindowTitle = "credits_window_title"
    tkCreditsHeader = "credits_header"
    tkCreditsRole = "credits_role"
    tkCreditsBuiltWith = "credits_built_with"
    tkCreditsThanks = "credits_thanks"
    tkCreditsThanksBody = "credits_thanks_body"
    tkCreditsLicense = "credits_license"
    tkSupportTitle = "support_title"
    tkSupportBlurb = "support_blurb"
    tkSupportNote = "support_note"

    # Changelog window
    tkChangelogWindowTitle = "changelog_window_title"
    tkChangelogHeader = "changelog_header"
    tkChangelogSince = "changelog_since"
    tkChangelogLatest = "changelog_latest"
    tkChangelogCatNew = "changelog_cat_new"
    tkChangelogCatImproved = "changelog_cat_improved"
    tkChangelogCatBalance = "changelog_cat_balance"
    tkChangelogCatFixed = "changelog_cat_fixed"

    # Settings
    tkSettingsTitle = "settings_title"
    tkSettingsFpsLimit = "settings_fps_limit"
    tkSettingsClickEdit = "settings_click_edit"
    tkSettingsSoundEffects = "settings_sound_effects"
    tkSettingsMusic = "settings_music"
    tkSettingsSoundEffectsDesc = "settings_sound_effects_desc"
    tkSettingsMusicDesc = "settings_music_desc"
    tkSettingsFullscreen = "settings_fullscreen"
    tkSettingsFullscreenToggle = "settings_fullscreen_toggle"
    tkSettingsRenderResolution = "settings_render_resolution"
    tkSettingsRenderResolutionDesc = "settings_render_resolution_desc"
    tkSettingsRenderResolutionDisabled = "settings_render_resolution_disabled"
    tkSettingsRenderResolutionEnabled = "settings_render_resolution_enabled"
    tkSettingsRenderResolutionFullscreenOnly = "settings_render_resolution_fullscreen_only"
    tkSettingsVSync = "settings_vsync"
    tkSettingsVSyncDesc = "settings_vsync_desc"
    tkSettingsShowFps = "settings_show_fps"
    tkSettingsMouseSupport = "settings_mouse_support"
    tkSettingsMouseSupportDesc = "settings_mouse_support_desc"
    tkSettingsMouseBonding = "settings_mouse_bonding"
    tkSettingsMouseBondingDesc = "settings_mouse_bonding_desc"
    tkSettingsMouseBondingOff = "settings_mouse_bonding_off"
    tkSettingsMouseBondingWhileShooting = "settings_mouse_bonding_while_shooting"
    tkSettingsMouseBondingAlwaysInGame = "settings_mouse_bonding_always_in_game"
    tkSettingsMouseBondingAlways = "settings_mouse_bonding_always"
    tkSettingsShowCursor = "settings_show_cursor"
    tkSettingsShowCursorDesc = "settings_show_cursor_desc"
    tkSettingsDebugPanel = "settings_debug_panel"
    tkSettingsDebugPanelDesc = "settings_debug_panel_desc"
    tkSettingsArenaVignette = "settings_arena_vignette"
    tkSettingsArenaVignetteDesc = "settings_arena_vignette_desc"
    tkSettingsLowHealthVignette = "settings_low_health_vignette"
    tkSettingsLowHealthVignetteDesc = "settings_low_health_vignette_desc"
    tkSettingsShowHints = "settings_show_hints"
    tkSettingsShowHintsDesc = "settings_show_hints_desc"
    tkSettingsHudLayout = "settings_hud_layout"
    tkSettingsHudLayoutDesc = "settings_hud_layout_desc"
    tkSettingsHudLayoutClassic = "settings_hud_layout_classic"
    tkSettingsHudLayoutWidescreen = "settings_hud_layout_widescreen"
    tkSettingsShowEnemyLabels = "settings_show_enemy_labels"
    tkSettingsShowEnemyLabelsDesc = "settings_show_enemy_labels_desc"
    tkSettingsExitConfirm = "settings_exit_confirm"
    tkSettingsExitConfirmDesc = "settings_exit_confirm_desc"
    tkSettingsLanguage = "settings_language"
    tkSettingsReplayIntro = "settings_replay_intro"
    tkSettingsReplayEnding = "settings_replay_ending"
    tkSettingsReplayRogueliteEnding = "settings_replay_roguelite_ending"
    tkSettingsReplaySurvivalEnding = "settings_replay_survival_ending"
    tkSettingsReplayWaveIntro = "settings_replay_wave_intro"
    tkSettingsReplaySurvivalIntro = "settings_replay_survival_intro"
    tkSettingsReplayRogueliteIntro = "settings_replay_roguelite_intro"
    tkSettingsReplaySandboxIntro = "settings_replay_sandbox_intro"
    tkSettingsReplayPvPIntro = "settings_replay_pvp_intro"
    tkSettingsBackToMenu = "settings_back_to_menu"
    tkSettingsSectionDataManagement = "settings_section_data_management"
    tkSettingsResetAllData = "settings_reset_all_data"
    tkSettingsResetAdvancements = "settings_reset_advancements"
    tkSettingsResetRogueliteData = "settings_reset_roguelite_data"
    tkSettingsConfirmReset = "settings_confirm_reset"
    tkSettingsResetComplete = "settings_reset_complete"
    tkSettingsResetFailed = "settings_reset_failed"

    # Settings window tabs and sections
    tkSettingsTabGraphics = "settings_tab_graphics"
    tkSettingsTabAudio = "settings_tab_audio"
    tkSettingsTabControls = "settings_tab_controls"
    tkSettingsTabGameplay = "settings_tab_gameplay"
    tkSettingsTabCinematics = "settings_tab_cinematics"

    tkSettingsSectionStory = "settings_section_story"
    tkSettingsSectionModeIntros = "settings_section_mode_intros"
    tkSettingsSectionDisplay = "settings_section_display"
    tkSettingsSectionVolumeControl = "settings_section_volume_control"
    tkSettingsSectionInputMethod = "settings_section_input_method"
    tkSettingsSectionAssistance = "settings_section_assistance"
    tkSettingsSectionLocalization = "settings_section_localization"
    tkSettingsSectionKeyboardShortcuts = "settings_section_keyboard_shortcuts"

    tkSettingsKeyboardWASD = "settings_keyboard_wasd"
    tkSettingsKeyboardMovement = "settings_keyboard_movement"
    tkSettingsKeyboardMouseSpace = "settings_keyboard_mouse_space"
    tkSettingsKeyboardShoot = "settings_keyboard_shoot"
    tkSettingsKeyboardE = "settings_keyboard_e"
    tkSettingsKeyboardPlaceWall = "settings_keyboard_place_wall"
    tkSettingsKeyboardQ = "settings_keyboard_q"
    tkSettingsKeyboardLegendaryAbilities = "settings_keyboard_legendary_abilities"
    tkSettingsKeyboardESC = "settings_keyboard_esc"
    tkSettingsKeyboardPauseMenu = "settings_keyboard_pause_menu"
    tkSettingsKeyboardF11 = "settings_keyboard_f11"
    tkSettingsKeyboardToggleFullscreen = "settings_keyboard_toggle_fullscreen"
    tkSettingsKeyboardTab = "settings_keyboard_tab"

    # Rebindable keybinds UI
    tkSettingsSectionKeybindings = "settings_section_keybindings"
    tkKeybindMoveUp = "keybind_move_up"
    tkKeybindMoveDown = "keybind_move_down"
    tkKeybindMoveLeft = "keybind_move_left"
    tkKeybindMoveRight = "keybind_move_right"
    tkKeybindShoot = "keybind_shoot"
    tkKeybindPlaceWall = "keybind_place_wall"
    tkKeybindLegendary = "keybind_legendary"
    tkKeybindPressAnyKey = "keybind_press_any_key"
    tkKeybindResetDefaults = "keybind_reset_defaults"
    tkKeybindNonRebindableNote = "keybind_non_rebindable_note"
    tkGamepadColumnKey = "gamepad_column_key"
    tkGamepadColumnPad = "gamepad_column_pad"
    tkGamepadPressAnyButton = "gamepad_press_any_button"
    tkGamepadReservedNote = "gamepad_reserved_note"
    tkSettingsAimAssist = "settings_aim_assist"
    tkSettingsAimAssistDesc = "settings_aim_assist_desc"
    tkSettingsController = "settings_controller"
    tkSettingsControllerDesc = "settings_controller_desc"
    tkSettingsControllerAuto = "settings_controller_auto"
    tkSettingsControllerNone = "settings_controller_none"

    # Intro / Lore Cinematic
    tkLoreTitleCardSub = "lore_title_card_sub"
    tkLoreLive = "lore_live"
    tkLorePlayback = "lore_playback"
    tkLoreControlsFF = "lore_controls_ff"
    tkLoreControlsFFActive = "lore_controls_ff_active"
    tkLoreRecBreach = "lore_rec_breach"
    tkLoreRecSwarm = "lore_rec_swarm"
    tkLoreRecAwaken = "lore_rec_awaken"
    tkLoreRecBoss = "lore_rec_boss"
    tkLoreRecCounter = "lore_rec_counter"
    tkLoreRecDirective = "lore_rec_directive"
    tkLoreBreach1 = "lore_breach_1"
    tkLoreBreach2 = "lore_breach_2"
    tkLoreSwarm1 = "lore_swarm_1"
    tkLoreSwarm2 = "lore_swarm_2"
    tkLoreAwaken1 = "lore_awaken_1"
    tkLoreAwaken2 = "lore_awaken_2"
    tkLoreBoss1 = "lore_boss_1"
    tkLoreBoss2 = "lore_boss_2"
    tkLoreCounter1 = "lore_counter_1"
    tkLoreCounter2 = "lore_counter_2"
    tkLoreDirectiveTitle = "lore_directive_title"
    tkLoreDirectiveSub = "lore_directive_sub"

    # Endgame / Outro Cinematic
    tkEndTitleCardSub = "end_title_card_sub"
    tkEndRecFall = "end_rec_fall"
    tkEndRecPurge = "end_rec_purge"
    tkEndRecRestore = "end_rec_restore"
    tkEndRecCrown = "end_rec_crown"
    tkEndRecSignoff = "end_rec_signoff"
    tkEndFall1 = "end_fall_1"
    tkEndFall2 = "end_fall_2"
    tkEndPurge1 = "end_purge_1"
    tkEndPurge2 = "end_purge_2"
    tkEndRestore1 = "end_restore_1"
    tkEndRestore2 = "end_restore_2"
    tkEndCrown1 = "end_crown_1"
    tkEndCrown2 = "end_crown_2"
    tkEndSignoffTitle = "end_signoff_title"
    tkEndSignoffSub = "end_signoff_sub"

    # Roguelite Ending Cinematic ("Deep Recovery" / DELVE archive)
    tkRogEndTitleCardSub = "rog_end_title_card_sub"
    tkRogEndRecDescend = "rog_end_rec_descend"
    tkRogEndRecCore = "rog_end_rec_core"
    tkRogEndRecExtract = "rog_end_rec_extract"
    tkRogEndRecReveal = "rog_end_rec_reveal"
    tkRogEndRecAscend = "rog_end_rec_ascend"
    tkRogEndRecSignoff = "rog_end_rec_signoff"
    tkRogEndDescend1 = "rog_end_descend_1"
    tkRogEndDescend2 = "rog_end_descend_2"
    tkRogEndCore1 = "rog_end_core_1"
    tkRogEndCore2 = "rog_end_core_2"
    tkRogEndExtract1 = "rog_end_extract_1"
    tkRogEndExtract2 = "rog_end_extract_2"
    tkRogEndReveal1 = "rog_end_reveal_1"
    tkRogEndReveal2 = "rog_end_reveal_2"
    tkRogEndAscend1 = "rog_end_ascend_1"
    tkRogEndAscend2 = "rog_end_ascend_2"
    tkRogEndSignoffTitle = "rog_end_signoff_title"
    tkRogEndSignoffSub = "rog_end_signoff_sub"

    # Survival Ending Cinematic ("The Long Watch" / LOG archive)
    tkSurEndTitleCardSub = "sur_end_title_card_sub"
    tkSurEndRecWatch = "sur_end_rec_watch"
    tkSurEndRecSurge = "sur_end_rec_surge"
    tkSurEndRecFall = "sur_end_rec_fall"
    tkSurEndRecShutdown = "sur_end_rec_shutdown"
    tkSurEndRecSignoff = "sur_end_rec_signoff"
    tkSurEndWatch1 = "sur_end_watch_1"
    tkSurEndWatch2 = "sur_end_watch_2"
    tkSurEndSurge1 = "sur_end_surge_1"
    tkSurEndSurge2 = "sur_end_surge_2"
    tkSurEndFall1 = "sur_end_fall_1"
    tkSurEndFall2 = "sur_end_fall_2"
    tkSurEndShutdown1 = "sur_end_shutdown_1"
    tkSurEndShutdown2 = "sur_end_shutdown_2"
    tkSurEndSignoffTitle = "sur_end_signoff_title"
    tkSurEndSignoffSub = "sur_end_signoff_sub"

    # Stats Window
    tkStatsWindowTitle = "stats_window_title"
    tkStatsTabLifetime = "stats_tab_lifetime"
    tkStatsTabLastRun = "stats_tab_last_run"
    tkStatsTabPowerUps = "stats_tab_power_ups"
    tkStatsPerformanceMonitor = "stats_performance_monitor"
    tkStatsTotalSessions = "stats_total_sessions"
    tkStatsPlaytime = "stats_playtime"
    tkStatsPeakKills = "stats_peak_kills"
    tkStatsWaveModeMetrics = "stats_wave_mode_metrics"
    tkStatsTimeSurvivalMetrics = "stats_time_survival_metrics"
    tkStatsCombat = "stats_combat"
    tkStatsAccuracy = "stats_accuracy"
    tkStatsShotsFired = "stats_shots_fired"
    tkStatsShotsHit = "stats_shots_hit"
    tkStatsEliteKills = "stats_elite_kills"
    tkStatsBossKills = "stats_boss_kills"
    tkStatsCriticalHits = "stats_critical_hits"
    tkStatsMovementSurvival = "stats_movement_survival"
    tkStatsDistance = "stats_distance"
    tkStatsPhaseShifts = "stats_phase_shifts"
    tkStatsTimeWarps = "stats_time_warps"
    tkStatsNearDeaths = "stats_near_deaths"
    tkStatsBestStreak = "stats_best_streak"
    tkStatsTimeAtLowHP = "stats_time_at_low_hp"
    tkStatsPerformance = "stats_performance"
    tkStatsPeakDPS = "stats_peak_dps"
    tkStatsAverageDPS = "stats_average_dps"
    tkStatsKillsPerMin = "stats_kills_per_min"
    tkStatsAvgWave = "stats_avg_wave"
    tkStatsFastestWave = "stats_fastest_wave"
    tkStatsResources = "stats_resources"
    tkStatsCoinsEarned = "stats_coins_earned"
    tkStatsCoinsSpent = "stats_coins_spent"
    tkStatsCoinsSaved = "stats_coins_saved"
    tkStatsWallsPlaced = "stats_walls_placed"
    tkStatsConsumables = "stats_consumables"
    tkStatsShopPurchases = "stats_shop_purchases"
    tkStatsPlayStyle = "stats_play_style"
    tkStatsAggression = "stats_aggression"
    tkStatsCaution = "stats_caution"
    tkStatsDPSOverTime = "stats_dps_over_time"
    tkStatsNoGraphData = "stats_no_graph_data"
    tkStatsMaxCombo = "stats_max_combo"
    tkDesktopModeLocked = "desktop_mode_locked"
    tkSurvivalLockedDesc = "survival_locked_desc"
    tkRogueliteLockedDesc = "roguelite_locked_desc"
    tkGameModeUnlocked = "game_mode_unlocked"
    tkResumeRunTitle = "resume_run_title"
    tkResumeRunBody = "resume_run_body"
    tkResumeContinue = "resume_continue"
    tkResumeNewRun = "resume_new_run"
    tkRogueliteUnlockedNotif = "roguelite_unlocked_notif"
    tkSurvivalUnlockedNotif = "survival_unlocked_notif"
    tkStatsAvgCombo = "stats_avg_combo"
    tkStatsPerfectWaves = "stats_perfect_waves"
    tkStatsWaveMode = "stats_wave_mode"
    tkStatsTimeSurvivalMode = "stats_time_survival_mode"
    tkStatsSandboxMode = "stats_sandbox_mode"
    tkStatsPvPMode = "stats_pvp_mode"
    tkStatsCombatLabel = "stats_combat_label"
    tkStatsShotsFiredLabel = "stats_shots_fired_label"
    tkStatsShotsHitLabel = "stats_shots_hit_label"
    tkStatsNoPreviousRun = "stats_no_previous_run"
    tkStatsCompleteGameStats = "stats_complete_game_stats"
    tkStatsPowerUpBreakdown = "stats_power_up_breakdown"
    tkStatsTimeline = "stats_timeline"
    tkStatsEffectivenessRanking = "stats_effectiveness_ranking"
    tkStatsRank = "stats_rank"
    tkStatsPowerUp = "stats_power_up"
    tkStatsDamage = "stats_damage"
    tkStatsNoDamageData = "stats_no_damage_data"
    tkStatsNoPowerUpData = "stats_no_power_up_data"

    # Game Over Screen
    tkGameOverTitle = "game_over_title"
    tkGameOverSecure = "game_over_secure"
    tkGameOverPerformanceReport = "game_over_performance_report"
    tkGameOverWavesSurvived = "game_over_waves_survived"
    tkGameOverThreatsEliminated = "game_over_threats_eliminated"
    tkGameOverResourcesCollected = "game_over_resources_collected"
    tkGameOverMissionDuration = "game_over_mission_duration"
    tkGameOverContinue = "game_over_continue"
    tkGameOverSaveLog = "game_over_save_log"
    tkGameOverCriticalFailure = "game_over_critical_failure"
    tkGameOverErrorMsg = "game_over_error_msg"
    tkGameOverSessionDiagnostics = "game_over_session_diagnostics"
    tkGameOverWaveReached = "game_over_wave_reached"
    tkGameOverSystemUptime = "game_over_system_uptime"
    tkGameOverRestartSystem = "game_over_restart_system"
    tkGameOverViewLogs = "game_over_view_logs"
    tkGameOverExit = "game_over_exit"
    tkGameOverErrorCode = "game_over_error_code"
    tkGameOverSecurityLevelMax = "game_over_security_level_max"
    tkGameOverSystemFailedFooter = "game_over_system_failed_footer"
    tkGameOverSystemSecureFooter = "game_over_system_secure_footer"

    # Victory Screen (wave 60 final boss cleared)
    tkVictoryTitle = "victory_title"
    tkVictorySubtitle = "victory_subtitle"
    tkVictoryStatus = "victory_status"
    tkVictoryReportHeader = "victory_report_header"
    tkVictoryBossesDefeated = "victory_bosses_defeated"
    tkVictoryContinueEndless = "victory_continue_endless"
    tkVictoryViewStats = "victory_view_stats"
    tkVictoryReturnMenu = "victory_return_menu"
    tkVictoryFooter = "victory_footer"

    # Game Over "cause of death" lines
    tkGameOverCauseLabel = "game_over_cause_label"
    tkDeathContact = "death_contact"
    tkDeathBossContact = "death_boss_contact"
    tkDeathProjectile = "death_projectile"
    tkDeathLaser = "death_laser"
    tkDeathExplosion = "death_explosion"
    tkDeathMeteorite = "death_meteorite"
    tkDeathPoison = "death_poison"
    tkDeathHazard = "death_hazard"
    tkDeathUnknown = "death_unknown"
    tkDeathBossTag = "death_boss_tag"

    # HUD/Notifications
    tkHUDSystemStatus = "hud_system_status"
    tkHUDIntegrity = "hud_integrity"
    tkHUDCharges = "hud_charges"
    tkHUDProcesses = "hud_processes"
    tkHUDCache = "hud_cache"
    tkHUDPerformance = "hud_performance"
    tkHUDWave = "hud_wave"
    tkHUDUptime = "hud_uptime"
    tkHUDThreats = "hud_threats"
    tkNotifWaveInitiated = "notif_wave_initiated"

    # Debug Panel
    tkDebugPanelDiagnostics = "debug_panel_diagnostics"
    tkDebugPanelFPS = "debug_panel_fps"
    tkDebugPanelEntities = "debug_panel_entities"
    tkDebugPanelActiveEffects = "debug_panel_active_effects"
    tkDebugPanelCombatStats = "debug_panel_combat_stats"
    tkDebugPanelDamage = "debug_panel_damage"
    tkDebugPanelFireRate = "debug_panel_fire_rate"
    tkDebugPanelSpeed = "debug_panel_speed"
    tkDebugPanelLowHPBonuses = "debug_panel_low_hp_bonuses"
    tkDebugPanelRage = "debug_panel_rage"
    tkDebugPanelBerserker = "debug_panel_berserker"
    tkDebugPanelEffectSpeed = "debug_panel_effect_speed"
    tkDebugPanelEffectInvuln = "debug_panel_effect_invuln"
    tkDebugPanelEffectFire = "debug_panel_effect_fire"
    tkDebugPanelEffectMagnet = "debug_panel_effect_magnet"
    tkDebugPanelEffectTimeWarp = "debug_panel_effect_time_warp"
    tkDebugPanelEffectPhase = "debug_panel_effect_phase"
    tkDebugPanelEffectParry = "debug_panel_effect_parry"
    tkDebugPanelActive = "debug_panel_active"
    tkDebugPanelRunStats = "debug_panel_run_stats"
    tkDebugPanelWaveLabel = "debug_panel_wave_label"
    tkDebugPanelTimeLabel = "debug_panel_time_label"
    tkShopTabPlayer = "shop_tab_player"
    tkShopTabBullet = "shop_tab_bullet"
    tkShopTabBulletShapes = "shop_tab_bshapes"
    tkShopTabShapes = "shop_tab_shapes"
    tkShopTabParticles = "shop_tab_particles"
    tkShopScrollHint = "shop_scroll_hint"
    tkShopClickEquip = "shop_click_equip"
    tkShopWindowTitle = "shop_window_title"
    tkShopEquipped = "shop_equipped"
    tkShopCurrentlyEquipped = "shop_currently_equipped"
    tkShopCustomizeAppearance = "shop_customize_appearance"
    tkShopCustomizeBullets = "shop_customize_bullets"
    tkShopChooseShape = "shop_choose_shape"
    tkShopCustomizeEffects = "shop_customize_effects"

    # Player Skins
    tkSkinDefault = "skin_default"
    tkSkinDefaultDesc = "skin_default_desc"
    tkSkinNeonPink = "skin_neon_pink"
    tkSkinNeonPinkDesc = "skin_neon_pink_desc"
    tkSkinEmerald = "skin_emerald"
    tkSkinEmeraldDesc = "skin_emerald_desc"
    tkSkinSunset = "skin_sunset"
    tkSkinSunsetDesc = "skin_sunset_desc"
    tkSkinAmethyst = "skin_amethyst"
    tkSkinAmethystDesc = "skin_amethyst_desc"
    tkSkinGold = "skin_gold"
    tkSkinGoldDesc = "skin_gold_desc"
    tkSkinIce = "skin_ice"
    tkSkinIceDesc = "skin_ice_desc"
    tkSkinShadow = "skin_shadow"
    tkSkinShadowDesc = "skin_shadow_desc"
    tkSkinRainbow = "skin_rainbow"
    tkSkinRainbowDesc = "skin_rainbow_desc"
    tkSkinMatrix = "skin_matrix"
    tkSkinMatrixDesc = "skin_matrix_desc"
    tkSkinVoid = "skin_void"
    tkSkinVoidDesc = "skin_void_desc"
    tkSkinPlasma = "skin_plasma"
    tkSkinPlasmaDesc = "skin_plasma_desc"

    # Bullet Skins
    tkBulletDefault = "bullet_default"
    tkBulletDefaultDesc = "bullet_default_desc"
    tkBulletNeonPink = "bullet_neon_pink"
    tkBulletNeonPinkDesc = "bullet_neon_pink_desc"
    tkBulletEmerald = "bullet_emerald"
    tkBulletEmeraldDesc = "bullet_emerald_desc"
    tkBulletSunset = "bullet_sunset"
    tkBulletSunsetDesc = "bullet_sunset_desc"
    tkBulletAmethyst = "bullet_amethyst"
    tkBulletAmethystDesc = "bullet_amethyst_desc"
    tkBulletGold = "bullet_gold"
    tkBulletGoldDesc = "bullet_gold_desc"
    tkBulletIce = "bullet_ice"
    tkBulletIceDesc = "bullet_ice_desc"
    tkBulletShadow = "bullet_shadow"
    tkBulletShadowDesc = "bullet_shadow_desc"
    tkBulletRainbow = "bullet_rainbow"
    tkBulletRainbowDesc = "bullet_rainbow_desc"
    tkBulletMatrix = "bullet_matrix"
    tkBulletMatrixDesc = "bullet_matrix_desc"
    tkBulletVoid = "bullet_void"
    tkBulletVoidDesc = "bullet_void_desc"
    tkBulletPlasma = "bullet_plasma"
    tkBulletPlasmaDesc = "bullet_plasma_desc"

    # Shapes
    tkShapeHexagon = "shape_hexagon"
    tkShapeHexagonDesc = "shape_hexagon_desc"
    tkShapeTriangle = "shape_triangle"
    tkShapeTriangleDesc = "shape_triangle_desc"
    tkShapeSquare = "shape_square"
    tkShapeSquareDesc = "shape_square_desc"
    tkShapeCircle = "shape_circle"
    tkShapeCircleDesc = "shape_circle_desc"

    # Bullet Shapes
    tkBulletShapeCircle = "bshape_circle"
    tkBulletShapeCircleDesc = "bshape_circle_desc"
    tkBulletShapeTriangle = "bshape_triangle"
    tkBulletShapeTriangleDesc = "bshape_triangle_desc"
    tkBulletShapeDiamond = "bshape_diamond"
    tkBulletShapeDiamondDesc = "bshape_diamond_desc"
    tkBulletShapeSquare = "bshape_square"
    tkBulletShapeSquareDesc = "bshape_square_desc"
    tkBulletShapeStar = "bshape_star"
    tkBulletShapeStarDesc = "bshape_star_desc"
    tkBulletShapePentagon = "bshape_pentagon"
    tkBulletShapePentagonDesc = "bshape_pentagon_desc"
    tkShopCustomizeBulletShapes = "shop_customize_bshapes"

    # Particle Skins
    tkParticleDefault = "particle_default"
    tkParticleDefaultDesc = "particle_default_desc"
    tkParticleFire = "particle_fire"
    tkParticleFireDesc = "particle_fire_desc"
    tkParticleIce = "particle_ice"
    tkParticleIceDesc = "particle_ice_desc"
    tkParticleToxic = "particle_toxic"
    tkParticleToxicDesc = "particle_toxic_desc"
    tkParticlePlasma = "particle_plasma"
    tkParticlePlasmaDesc = "particle_plasma_desc"
    tkParticleGold = "particle_gold"
    tkParticleGoldDesc = "particle_gold_desc"
    tkParticleShadow = "particle_shadow"
    tkParticleShadowDesc = "particle_shadow_desc"
    tkParticleRainbow = "particle_rainbow"
    tkParticleRainbowDesc = "particle_rainbow_desc"
    tkParticleStars = "particle_stars"
    tkParticleStarsDesc = "particle_stars_desc"
    tkParticleHearts = "particle_hearts"
    tkParticleHeartsDesc = "particle_hearts_desc"
    tkParticleLightning = "particle_lightning"
    tkParticleLightningDesc = "particle_lightning_desc"
    tkParticleVoid = "particle_void"
    tkParticleVoidDesc = "particle_void_desc"

    # Legendary Panel
    tkLegendaryPanelTitle = "legendary_panel_title"
    tkLegendaryChronos = "legendary_chronos"
    tkLegendaryPhase = "legendary_phase"
    tkLegendaryParry = "legendary_parry"
    tkLegendaryActive = "legendary_active"
    tkLegendaryReady = "legendary_ready"
    tkLegendaryDashing = "legendary_dashing"
    tkLegendaryVolatile = "legendary_volatile"
    tkLegendaryResonance = "legendary_resonance"
    tkLegendaryBloodPact = "legendary_blood_pact"
    tkLegendaryConduit = "legendary_conduit"
    tkLegendaryNova = "legendary_nova"
    tkLegendaryPassive = "legendary_passive"
    tkLegendaryFrozen = "legendary_frozen"

    tkNotifWaveCleared = "notif_wave_cleared"
    tkNotifBossDetected = "notif_boss_detected"
    tkNotifBossTerminated = "notif_boss_terminated"
    tkNotifInstalled = "notif_installed"
    tkNotifIntegrityCompromised = "notif_integrity_compromised"
    tkNotifIntegrityRestored = "notif_integrity_restored"
    tkNotifResourceAcquired = "notif_resource_acquired"
    tkNotifExecute = "notif_execute"
    tkNotifCooldown = "notif_cooldown"
    tkNotifProcessTerminated = "notif_process_terminated"
    tkNotifProcessesTerminated = "notif_processes_terminated"

    # Help System
    tkHelpWindowTitle = "help_window_title"
    tkHelpAvailableCommands = "help_available_commands"
    tkHelpControlsKeybindings = "help_controls_keybindings"
    tkHelpGameplayTopic = "help_gameplay_topic"
    tkHelpPowerUpsTopic = "help_power_ups_topic"
    tkHelpPowerUpLockedName = "help_powerup_locked_name"
    tkHelpPowerUpLockedDesc = "help_powerup_locked_desc"
    tkHelpEnemiesTopic = "help_enemies_topic"
    tkHelpBossesTopic = "help_bosses_topic"
    tkHelpShopTopic = "help_shop_topic"
    tkHelpClearCommand = "help_clear_command"
    tkHelpCommandSeparator = "help_command_separator"
    tkHelpLaunchTopics = "help_launch_topics"
    tkHelpLaunchingIcon = "help_launching_icon"
    tkHelpOpeningIcon = "help_opening_icon"
    tkHelpExecutingIcon = "help_executing_icon"
    tkHelpUnknownCommand = "help_unknown_command"
    tkHelpTypeHelp = "help_type_help"
    tkHelpErrorExecuting = "help_error_executing"

    # Help System - Command descriptions
    tkHelpCmdHelp = "help_cmd_help"
    tkHelpCmdControls = "help_cmd_controls"
    tkHelpCmdGameplay = "help_cmd_gameplay"
    tkHelpCmdPowerups = "help_cmd_powerups"
    tkHelpCmdEnemies = "help_cmd_enemies"
    tkHelpCmdBosses = "help_cmd_bosses"
    tkHelpCmdShop = "help_cmd_shop"
    tkHelpCmdLaunchIcons = "help_cmd_launch_icons"

    # Help System - Controls section
    tkHelpMovement = "help_movement"
    tkHelpCombat = "help_combat"
    tkHelpAbilities = "help_abilities"
    tkHelpMenu = "help_menu"
    tkHelpMovementDesc = "help_movement_desc"
    tkHelpWASD = "help_wasd"
    tkHelpArrowKeys = "help_arrow_keys"
    tkHelpLeftMouse = "help_left_mouse"
    tkHelpSpace = "help_space"
    tkHelpQ = "help_q"
    tkHelpE = "help_e"
    tkHelpESC = "help_esc"
    tkHelpF11 = "help_f11"

    # Help System - Gameplay section
    tkHelpWaveMode = "help_wave_mode"
    tkHelpWaveModeDesc = "help_wave_mode_desc"
    tkHelpSurvivalMode = "help_survival_mode"
    tkHelpSurvivalModeDesc = "help_survival_mode_desc"
    tkHelpSandboxMode = "help_sandbox_mode"
    tkHelpSandboxModeDesc = "help_sandbox_mode_desc"

    # Help System - Power-ups section
    tkHelpCommonPowerups = "help_common_powerups"
    tkHelpElementalOrbs = "help_elemental_orbs"
    tkHelpElementalAuras = "help_elemental_auras"
    tkHelpLegendaryPowerups = "help_legendary_powerups"

    # Help System - Enemy section
    tkHelpEnemyCircle = "help_enemy_circle"
    tkHelpEnemyCube = "help_enemy_cube"
    tkHelpEnemyTriangle = "help_enemy_triangle"
    tkHelpEnemyStar = "help_enemy_star"
    tkHelpEnemyHexagon = "help_enemy_hexagon"
    tkHelpEnemyElite = "help_enemy_elite"

    # Help System - Boss section
    tkHelpBossSpawning = "help_boss_spawning"
    tkHelpBossMechanics = "help_boss_mechanics"
    tkHelpBossAttacks = "help_boss_attacks"
    tkHelpBossRewards = "help_boss_rewards"

    # Help System - Shop section
    tkHelpAvailableItems = "help_available_items"
    tkHelpCostScaling = "help_cost_scaling"
    tkHelpEarningCoins = "help_earning_coins"
    tkHelpShopAccess = "help_shop_access"

    # Help System - Powerup names
    tkHelpDoubleShot = "help_double_shot"
    tkHelpRotatingShield = "help_rotating_shield"
    tkHelpMagicalBullets = "help_magical_bullets"
    tkHelpPiercingShots = "help_piercing_shots"
    tkHelpMultiShot = "help_multi_shot"
    tkHelpExplosiveBullets = "help_explosive_bullets"
    tkHelpLifeSteal = "help_life_steal"
    tkHelpRapidFire = "help_rapid_fire"
    tkHelpMaxHealth = "help_max_health"
    tkHelpSpeedBoost = "help_speed_boost"
    tkHelpBulletSpeed = "help_bullet_speed"
    tkHelpLuckyCoins = "help_lucky_coins"
    tkHelpWallMaster = "help_wall_master"
    tkHelpRegeneration = "help_regeneration"
    tkHelpDodgeChance = "help_dodge_chance"
    tkHelpCriticalHit = "help_critical_hit"
    tkHelpBloodBullets = "help_blood_bullets"
    tkHelpBulletRicochet = "help_bullet_ricochet"
    tkHelpSlowField = "help_slow_field"
    tkHelpRage = "help_rage"
    tkHelpBerserker = "help_berserker"
    tkHelpThorns = "help_thorns"
    tkHelpBulletSplit = "help_bullet_split"
    tkHelpChainLightning = "help_chain_lightning"
    tkHelpFrostShots = "help_frost_shots"
    tkHelpPoisonShot = "help_poison_shot"
    tkHelpFireBullets = "help_fire_bullets"
    tkHelpWindBullets = "help_wind_bullets"
    tkHelpOvercharge = "help_overcharge"
    tkHelpEchoShots = "help_echo_shots"
    tkHelpPoisonOrb = "help_poison_orb"
    tkHelpFireOrb = "help_fire_orb"
    tkHelpLightningOrb = "help_lightning_orb"
    tkHelpWindOrb = "help_wind_orb"
    tkHelpFrostOrb = "help_frost_orb"
    tkHelpArcaneOrb = "help_arcane_orb"
    tkHelpBloodOrb = "help_blood_orb"
    tkHelpFireAura = "help_fire_aura"
    tkHelpLightningAura = "help_lightning_aura"
    tkHelpPoisonAura = "help_poison_aura"
    tkHelpWindAura = "help_wind_aura"
    tkHelpArcaneAura = "help_arcane_aura"
    tkHelpBloodAura = "help_blood_aura"
    tkHelpTimeWarp = "help_time_warp"
    tkHelpGravityWell = "help_gravity_well"
    tkHelpPhaseShift = "help_phase_shift"
    tkHelpParry = "help_parry"
    tkHelpRotatingOrbs = "help_rotating_orbs"
    tkHelpFireMastery = "help_fire_mastery"
    tkHelpPoisonMastery = "help_poison_mastery"
    tkHelpFrostMastery = "help_frost_mastery"
    tkHelpArcaneMastery = "help_arcane_mastery"
    tkHelpLightningMastery = "help_lightning_mastery"
    tkHelpWindMastery = "help_wind_mastery"
    tkHelpBloodMastery = "help_blood_mastery"
    tkHelpArcaneBullets = "help_arcane_bullets"
    tkHelpRadialBurst = "help_radial_burst"
    tkHelpWallTurrets = "help_wall_turrets"
    tkHelpPulseArmor = "help_pulse_armor"
    tkHelpHeavyRounds = "help_heavy_rounds"
    tkHelpFortified = "help_fortified"
    tkHelpSpecialRounds = "help_special_rounds"
    tkHelpGiantSlayer = "help_giant_slayer"
    tkHelpCurse = "help_curse"
    tkHelpCelestialVeil = "help_celestial_veil"
    tkHelpVolatile = "help_volatile"
    tkHelpResonance = "help_resonance"
    tkHelpBloodPact = "help_blood_pact"
    tkHelpConduit = "help_conduit"
    tkHelpAftershock = "help_aftershock"
    tkHelpNova = "help_nova"
    tkHelpHealPower = "help_heal_power"
    tkHelpBountiful = "help_bountiful"

    # Help System - Shop items
    tkHelpShopDamagePlus = "help_shop_damage_plus"
    tkHelpShopDamagePlusDesc = "help_shop_damage_plus_desc"
    tkHelpShopFireRatePlus = "help_shop_fire_rate_plus"
    tkHelpShopFireRatePlusDesc = "help_shop_fire_rate_plus_desc"
    tkHelpShopMoveSpeedPlus = "help_shop_move_speed_plus"
    tkHelpShopMoveSpeedPlusDesc = "help_shop_move_speed_plus_desc"
    tkHelpShopMaxHealthPlus = "help_shop_max_health_plus"
    tkHelpShopMaxHealthPlusDesc = "help_shop_max_health_plus_desc"
    tkHelpShopBulletSpeedPlus = "help_shop_bullet_speed_plus"
    tkHelpShopBulletSpeedPlusDesc = "help_shop_bullet_speed_plus_desc"
    tkHelpShopWallX4 = "help_shop_wall_x4"
    tkHelpShopWallX4Desc = "help_shop_wall_x4_desc"

    # Help System - Misc
    tkHelpWaveModeInfo = "help_wave_mode_info"
    tkHelpSurvivalModeInfo = "help_survival_mode_info"
    tkHelpEnemyChaser = "help_enemy_chaser"
    tkHelpEnemyTurret = "help_enemy_turret"
    tkHelpEnemyDasher = "help_enemy_dasher"
    tkHelpEnemyTank = "help_enemy_tank"
    tkHelpEnemyWarper = "help_enemy_warper"
    tkHelpEnemyEliteDesc = "help_enemy_elite_desc"
    tkHelpBossEvery5th = "help_boss_every_5th"
    tkHelpBossEvery60Sec = "help_boss_every_60_sec"
    tkHelpCostScalingFormula = "help_cost_scaling_formula"
    tkHelpKillEnemiesToCollect = "help_kill_enemies_to_collect"
    tkHelpEliteDropMore = "help_elite_drop_more"
    tkHelpBossDropLarge = "help_boss_drop_large"
    tkHelpOpensAfterPowerup = "help_opens_after_powerup"
    tkHelpAvailableBetweenWaves = "help_available_between_waves"

    # Game Notifications and UI
    tkGameWaveAnnouncementMain = "game_wave_announcement_main"
    tkGameInstructionsWall = "game_instructions_wall"
    tkGameWallPlace = "game_wall_place"
    tkGameWallPlaceRemaining = "game_wall_place_remaining"
    tkGameGetReady = "game_get_ready"
    tkGameBossWavePrefix = "game_boss_wave_prefix"
    tkGameIncoming = "game_incoming"
    tkGamePressEnterToStart = "game_press_enter_to_start"
    tkGameNoData = "game_no_data"
    tkGameNoGraphData = "game_no_graph_data"
    tkGameNoPreviousRun = "game_no_previous_run"
    tkGameCompleteGameStats = "game_complete_game_stats"
    tkGameNoPowerUpData = "game_no_power_up_data"
    tkGameWaveLabel = "game_wave_label"
    tkGameBestStreak = "game_best_streak"

    # Stats Window
    tkStatsTimeColumnLabel = "stats_time_column_label"
    tkStatsDamageColumnLabel = "stats_damage_column_label"
    tkStatsDealedAbbrev = "stats_dealed_abbrev"
    tkStatsTakenAbbrev = "stats_taken_abbrev"
    tkStatsLevelPrefix = "stats_level_prefix"
    tkStatsTotal = "stats_total"
    tkStatsLegendaryCount = "stats_legendary_count"
    tkStatsCommonCount = "stats_common_count"

    # Sandbox Mode
    tkSandboxSpawnEnemies = "sandbox_spawn_enemies"
    tkSandboxSpawn10Random = "sandbox_spawn_10_random"
    tkSandboxSpawnBosses = "sandbox_spawn_bosses"
    tkSandboxGodMode = "sandbox_god_mode"
    tkSandboxFreezeEnemies = "sandbox_freeze_enemies"
    tkSandboxClearAllEnemies = "sandbox_clear_all_enemies"
    tkSandboxWave = "sandbox_wave"
    tkSandboxDifficulty = "sandbox_difficulty"
    tkSandboxHP = "sandbox_hp"
    tkSandboxEnemies = "sandbox_enemies"
    tkSandboxHealFull = "sandbox_heal_full"
    tkSandboxAddCoins = "sandbox_add_coins"
    tkSandboxOpenShop = "sandbox_open_shop"
    tkSandboxRollPowerUps = "sandbox_roll_power_ups"
    tkSandboxTitle = "sandbox_title"
    tkSandboxTabEnemies = "sandbox_tab_enemies"
    tkSandboxTabBosses = "sandbox_tab_bosses"
    tkSandboxTabControls = "sandbox_tab_controls"
    tkSandboxCoins = "sandbox_coins"
    tkSandboxWaveMinus = "sandbox_wave_minus"
    tkSandboxWavePlus = "sandbox_wave_plus"
    tkSandboxDiffMinus = "sandbox_diff_minus"
    tkSandboxDiffPlus = "sandbox_diff_plus"
    tkSandboxToggle = "sandbox_toggle"
    tkSandboxClose = "sandbox_close"

    # Cheat Menu
    tkCheatMenuTitle = "cheat_menu_title"
    tkCheatMenuClose = "cheat_menu_close"
    tkCheatTabWaves = "cheat_tab_waves"
    tkCheatTabPower = "cheat_tab_power"
    tkCheatTabStats = "cheat_tab_stats"
    tkCheatTabPerma = "cheat_tab_perma"
    tkCheatTabEnemies = "cheat_tab_enemies"
    tkCheatCurrentWave = "cheat_current_wave"
    tkCheatWavesUntilBoss = "cheat_waves_until_boss"
    tkCheatEnemiesAlive = "cheat_enemies_alive"
    tkCheatSkipWave = "cheat_skip_wave"
    tkCheatAdvanceWave = "cheat_advance_wave"
    tkCheatTriggerBoss = "cheat_trigger_boss"
    tkCheatActivateConsumable = "cheat_activate_consumable"
    tkCheatSpeedBoost = "cheat_speed_boost"
    tkCheatInvincibility = "cheat_invincibility"
    tkCheatFireRate = "cheat_fire_rate"
    tkCheatMagnet = "cheat_magnet"
    tkCheatPlayerStats = "cheat_player_stats"
    tkCheatHealth = "cheat_health"
    tkCheatMaxHealth = "cheat_max_health"
    tkCheatCoins = "cheat_coins"
    tkCheatSpeed = "cheat_speed"
    tkCheatHealthFull = "cheat_health_full"
    tkCheatHealthHalf = "cheat_health_half"
    tkCheatHealthLow = "cheat_health_low"
    tkCheatHealthNum = "cheat_health_num"
    tkCheatSpeedNormal = "cheat_speed_normal"
    tkCheatSpeedFast = "cheat_speed_fast"
    tkCheatSpeedMax = "cheat_speed_max"
    tkCheatModifyStats = "cheat_modify_stats"
    tkCheatPowerUpsAvailable = "cheat_power_ups_available"
    tkCheatCurrentlyOwned = "cheat_currently_owned"
    tkCheatNone = "cheat_none"
    tkCheatAllPowerUps = "cheat_all_power_ups"
    tkCheatActiveEnemies = "cheat_active_enemies"
    tkCheatNoEnemies = "cheat_no_enemies"
    tkCheatDiscoveryCodex = "cheat_discovery_codex"
    tkCheatDiscoverAll = "cheat_discover_all"
    tkCheatUndiscoverAll = "cheat_undiscover_all"

    # Power-up Installer
    tkPowerUpInstallerTitle = "power_up_installer_title"
    tkPowerUpInstallerTitleGeneric = "power_up_installer_title_generic"
    tkPowerUpUpgradeTier = "power_up_upgrade_tier"
    tkPowerUpInstallerClose = "power_up_installer_close"
    tkPowerUpSelectUpgrade = "power_up_select_upgrade"
    tkPowerUpRolling = "power_up_rolling"
    tkPowerUpRerollOptions = "power_up_reroll_options"
    tkPowerUpAllInstalled = "power_up_all_installed"
    tkPowerUpAllInstalledMsg = "power_up_all_installed_msg"
    tkPowerUpContinue = "power_up_continue"
    tkPowerUpNewBadge = "power_up_new_badge"
    tkGamePause = "game_pause"
    tkGameResume = "game_resume"
    tkGameRestart = "game_restart"
    tkGameMainMenu = "game_main_menu"
    tkGameOver = "game_over"
    tkGameScore = "game_score"
    tkGameWave = "game_wave"
    tkGameHealth = "game_health"
    tkGameCoins = "game_coins"
    tkGameStatus = "game_status"
    tkGameWaveInfo = "game_wave_info"
    tkGameActive = "game_active"
    tkGameBoss = "game_boss"
    tkGameBossFight = "game_boss_fight"
    tkGameCollect = "game_collect"
    tkGameLeft = "game_left"
    tkGameCharges = "game_charges"
    tkGameProcesses = "game_processes"

    # Shop/Powerups
    tkShopTitle = "shop_title"
    tkShopBuy = "shop_buy"
    tkShopUpgrade = "shop_upgrade"
    tkShopCost = "shop_cost"
    tkShopOwned = "shop_owned"
    tkShopCreditStore = "shop_credit_store"
    tkShopUpgradesAvailable = "shop_upgrades_available"
    tkShopActiveUpgrades = "shop_active_upgrades"
    tkShopAvailablePurchases = "shop_available_purchases"
    tkShopControls = "shop_controls"
    tkShopNavigate = "shop_navigate"
    tkShopContinue = "shop_continue"
    tkShopBuySelected = "shop_buy_selected"
    tkShopInsufficientCredits = "shop_insufficient_credits"
    tkShopNoPermanent = "shop_no_permanent"
    tkShopDefeatWaves = "shop_defeat_waves"
    tkShopCredits = "shop_credits"
    tkShopBought = "shop_bought"
    tkShopDamagePlus = "shop_damage_plus"
    tkShopDamagePlusDesc = "shop_damage_plus_desc"
    tkShopFireRatePlus = "shop_fire_rate_plus"
    tkShopFireRatePlusDesc = "shop_fire_rate_plus_desc"
    tkShopMoveSpeedPlus = "shop_move_speed_plus"
    tkShopMoveSpeedPlusDesc = "shop_move_speed_plus_desc"
    tkShopMaxHealthPlus = "shop_max_health_plus"
    tkShopMaxHealthPlusDesc = "shop_max_health_plus_desc"
    tkShopBulletSpeedPlus = "shop_bullet_speed_plus"
    tkShopBulletSpeedPlusDesc = "shop_bullet_speed_plus_desc"
    tkShopWallX4 = "shop_wall_x4"
    tkShopWallX4Desc = "shop_wall_x4_desc"

    # Powerup Names
    tkPowerupDoubleShot = "powerup_double_shot"
    tkPowerupRotatingShield = "powerup_rotating_shield"
    tkPowerupMagicalBullets = "powerup_magical_bullets"
    tkPowerupPiercingShots = "powerup_piercing_shots"
    tkPowerupMultiShot = "powerup_multi_shot"
    tkPowerupExplosiveBullets = "powerup_explosive_bullets"
    tkPowerupLifeSteal = "powerup_life_steal"
    tkPowerupRapidFire = "powerup_rapid_fire"
    tkPowerupMaxHealth = "powerup_max_health"
    tkPowerupSpeedBoost = "powerup_speed_boost"
    tkPowerupBulletSpeed = "powerup_bullet_speed"
    tkPowerupLuckyCoins = "powerup_lucky_coins"
    tkPowerupWallMaster = "powerup_wall_master"
    tkPowerupRegeneration = "powerup_regeneration"
    tkPowerupDodgeChance = "powerup_dodge_chance"
    tkPowerupCriticalHit = "powerup_critical_hit"
    tkPowerupBloodBullets = "powerup_blood_bullets"
    tkPowerupBulletRicochet = "powerup_bullet_ricochet"
    tkPowerupSlowField = "powerup_slow_field"
    tkPowerupRage = "powerup_rage"
    tkPowerupBerserker = "powerup_berserker"
    tkPowerupThorns = "powerup_thorns"
    tkPowerupBulletSplit = "powerup_bullet_split"
    tkPowerupChainLightning = "powerup_chain_lightning"
    tkPowerupFrostShots = "powerup_frost_shots"
    tkPowerupPoisonShot = "powerup_poison_shot"
    tkPowerupFireBullets = "powerup_fire_bullets"
    tkPowerupWindBullets = "powerup_wind_bullets"
    tkPowerupFireAura = "powerup_fire_aura"
    tkPowerupLightningAura = "powerup_lightning_aura"
    tkPowerupPoisonAura = "powerup_poison_aura"
    tkPowerupWindAura = "powerup_wind_aura"
    tkPowerupTimeWarp = "powerup_time_warp"
    tkPowerupGravityWell = "powerup_gravity_well"
    tkPowerupPhaseShift = "powerup_phase_shift"
    tkPowerupOvercharge = "powerup_overcharge"
    tkPowerupEchoShots = "powerup_echo_shots"
    tkPowerupRotatingOrbs = "powerup_rotating_orbs"
    tkPowerupPoisonOrb = "powerup_poison_orb"
    tkPowerupFireOrb = "powerup_fire_orb"
    tkPowerupLightningOrb = "powerup_lightning_orb"
    tkPowerupWindOrb = "powerup_wind_orb"
    tkPowerupFrostOrb = "powerup_frost_orb"
    tkPowerupArcaneBullets = "powerup_arcane_bullets"
    tkPowerupArcaneAura = "powerup_arcane_aura"
    tkPowerupArcaneOrb = "powerup_arcane_orb"
    tkPowerupFireMastery = "powerup_fire_mastery"
    tkPowerupPoisonMastery = "powerup_poison_mastery"
    tkPowerupFrostMastery = "powerup_frost_mastery"
    tkPowerupArcaneMastery = "powerup_arcane_mastery"
    tkPowerupLightningMastery = "powerup_lightning_mastery"
    tkPowerupWindMastery = "powerup_wind_mastery"
    tkPowerupParry = "powerup_parry"
    tkPowerupBloodOrb = "powerup_blood_orb"
    tkPowerupBloodAura = "powerup_blood_aura"
    tkPowerupBloodMastery = "powerup_blood_mastery"
    tkPowerupRadialBurst = "powerup_radial_burst"
    tkPowerupWallTurrets = "powerup_wall_turrets"
    tkPowerupPulseArmor = "powerup_pulse_armor"
    tkPowerupHeavyRounds = "powerup_heavy_rounds"
    tkPowerupFortified = "powerup_fortified"
    tkPowerupSpecialRounds = "powerup_special_rounds"
    tkPowerupGiantSlayer = "powerup_giant_slayer"
    tkPowerupCurse = "powerup_curse"

    # Powerup Descriptions
    tkPowerupDoubleShotDesc = "powerup_double_shot_desc"
    tkPowerupRotatingShieldDesc1 = "powerup_rotating_shield_desc1"
    tkPowerupRotatingShieldDesc2 = "powerup_rotating_shield_desc2"
    tkPowerupRotatingShieldDesc3 = "powerup_rotating_shield_desc3"
    tkPowerupMagicalBulletsDesc = "powerup_magical_bullets_desc"
    tkPowerupPiercingShotsDesc1 = "powerup_piercing_shots_desc1"
    tkPowerupPiercingShotsDesc2 = "powerup_piercing_shots_desc2"
    tkPowerupPiercingShotsDesc3 = "powerup_piercing_shots_desc3"
    tkPowerupMultiShotDesc = "powerup_multi_shot_desc"
    tkPowerupExplosiveBulletsDesc1 = "powerup_explosive_bullets_desc1"
    tkPowerupExplosiveBulletsDesc2 = "powerup_explosive_bullets_desc2"
    tkPowerupExplosiveBulletsDesc3 = "powerup_explosive_bullets_desc3"
    tkPowerupLifeStealDesc1 = "powerup_life_steal_desc1"
    tkPowerupLifeStealDesc2 = "powerup_life_steal_desc2"
    tkPowerupLifeStealDesc3 = "powerup_life_steal_desc3"
    tkPowerupRapidFireDesc = "powerup_rapid_fire_desc"
    tkPowerupMaxHealthDesc = "powerup_max_health_desc"
    tkPowerupSpeedBoostDesc = "powerup_speed_boost_desc"
    tkPowerupBulletSpeedDesc = "powerup_bullet_speed_desc"
    tkPowerupLuckyCoinsDesc = "powerup_lucky_coins_desc"
    tkPowerupWallMasterDesc = "powerup_wall_master_desc"
    tkPowerupRegenerationDesc1 = "powerup_regeneration_desc1"
    tkPowerupRegenerationDesc2 = "powerup_regeneration_desc2"
    tkPowerupRegenerationDesc3 = "powerup_regeneration_desc3"
    tkPowerupDodgeChanceDesc1 = "powerup_dodge_chance_desc1"
    tkPowerupDodgeChanceDesc2 = "powerup_dodge_chance_desc2"
    tkPowerupDodgeChanceDesc3 = "powerup_dodge_chance_desc3"
    tkPowerupCriticalHitDesc1 = "powerup_critical_hit_desc1"
    tkPowerupCriticalHitDesc2 = "powerup_critical_hit_desc2"
    tkPowerupCriticalHitDesc3 = "powerup_critical_hit_desc3"
    tkPowerupBloodBulletsDesc1 = "powerup_blood_bullets_desc1"
    tkPowerupBloodBulletsDesc2 = "powerup_blood_bullets_desc2"
    tkPowerupBloodBulletsDesc3 = "powerup_blood_bullets_desc3"
    tkPowerupBulletRicochetDesc1 = "powerup_bullet_ricochet_desc1"
    tkPowerupBulletRicochetDesc2 = "powerup_bullet_ricochet_desc2"
    tkPowerupBulletRicochetDesc3 = "powerup_bullet_ricochet_desc3"
    tkPowerupSlowFieldDesc1 = "powerup_slow_field_desc1"
    tkPowerupSlowFieldDesc2 = "powerup_slow_field_desc2"
    tkPowerupSlowFieldDesc3 = "powerup_slow_field_desc3"
    tkPowerupRageDesc1 = "powerup_rage_desc1"
    tkPowerupRageDesc2 = "powerup_rage_desc2"
    tkPowerupRageDesc3 = "powerup_rage_desc3"
    tkPowerupBerserkerDesc1 = "powerup_berserker_desc1"
    tkPowerupBerserkerDesc2 = "powerup_berserker_desc2"
    tkPowerupBerserkerDesc3 = "powerup_berserker_desc3"
    tkPowerupThornsDesc1 = "powerup_thorns_desc1"
    tkPowerupThornsDesc2 = "powerup_thorns_desc2"
    tkPowerupThornsDesc3 = "powerup_thorns_desc3"
    tkPowerupBulletSplitDesc1 = "powerup_bullet_split_desc1"
    tkPowerupBulletSplitDesc2 = "powerup_bullet_split_desc2"
    tkPowerupBulletSplitDesc3 = "powerup_bullet_split_desc3"
    tkPowerupChainLightningDesc1 = "powerup_chain_lightning_desc1"
    tkPowerupChainLightningDesc2 = "powerup_chain_lightning_desc2"
    tkPowerupChainLightningDesc3 = "powerup_chain_lightning_desc3"
    tkPowerupFrostShotsDesc1 = "powerup_frost_shots_desc1"
    tkPowerupFrostShotsDesc2 = "powerup_frost_shots_desc2"
    tkPowerupFrostShotsDesc3 = "powerup_frost_shots_desc3"
    tkPowerupPoisonShotDesc1 = "powerup_poison_shot_desc1"
    tkPowerupPoisonShotDesc2 = "powerup_poison_shot_desc2"
    tkPowerupPoisonShotDesc3 = "powerup_poison_shot_desc3"
    tkPowerupFireBulletsDesc1 = "powerup_fire_bullets_desc1"
    tkPowerupFireBulletsDesc2 = "powerup_fire_bullets_desc2"
    tkPowerupFireBulletsDesc3 = "powerup_fire_bullets_desc3"
    tkPowerupWindBulletsDesc1 = "powerup_wind_bullets_desc1"
    tkPowerupWindBulletsDesc2 = "powerup_wind_bullets_desc2"
    tkPowerupWindBulletsDesc3 = "powerup_wind_bullets_desc3"
    tkPowerupFireAuraDesc1 = "powerup_fire_aura_desc1"
    tkPowerupFireAuraDesc2 = "powerup_fire_aura_desc2"
    tkPowerupFireAuraDesc3 = "powerup_fire_aura_desc3"
    tkPowerupLightningAuraDesc1 = "powerup_lightning_aura_desc1"
    tkPowerupLightningAuraDesc2 = "powerup_lightning_aura_desc2"
    tkPowerupLightningAuraDesc3 = "powerup_lightning_aura_desc3"
    tkPowerupPoisonAuraDesc1 = "powerup_poison_aura_desc1"
    tkPowerupPoisonAuraDesc2 = "powerup_poison_aura_desc2"
    tkPowerupPoisonAuraDesc3 = "powerup_poison_aura_desc3"
    tkPowerupWindAuraDesc1 = "powerup_wind_aura_desc1"
    tkPowerupWindAuraDesc2 = "powerup_wind_aura_desc2"
    tkPowerupWindAuraDesc3 = "powerup_wind_aura_desc3"
    tkPowerupTimeWarpDesc = "powerup_time_warp_desc"
    tkPowerupGravityWellDesc = "powerup_gravity_well_desc"
    tkPowerupPhaseShiftDesc = "powerup_phase_shift_desc"
    tkPowerupOverchargeDesc = "powerup_overcharge_desc"
    tkPowerupEchoShotsDesc = "powerup_echo_shots_desc"
    tkPowerupRotatingOrbsDesc = "powerup_rotating_orbs_desc"
    tkPowerupPoisonOrbDesc1 = "powerup_poison_orb_desc1"
    tkPowerupPoisonOrbDesc2 = "powerup_poison_orb_desc2"
    tkPowerupPoisonOrbDesc3 = "powerup_poison_orb_desc3"
    tkPowerupFireOrbDesc1 = "powerup_fire_orb_desc1"
    tkPowerupFireOrbDesc2 = "powerup_fire_orb_desc2"
    tkPowerupFireOrbDesc3 = "powerup_fire_orb_desc3"
    tkPowerupLightningOrbDesc1 = "powerup_lightning_orb_desc1"
    tkPowerupLightningOrbDesc2 = "powerup_lightning_orb_desc2"
    tkPowerupLightningOrbDesc3 = "powerup_lightning_orb_desc3"
    tkPowerupWindOrbDesc1 = "powerup_wind_orb_desc1"
    tkPowerupWindOrbDesc2 = "powerup_wind_orb_desc2"
    tkPowerupWindOrbDesc3 = "powerup_wind_orb_desc3"
    tkPowerupFrostOrbDesc1 = "powerup_frost_orb_desc1"
    tkPowerupFrostOrbDesc2 = "powerup_frost_orb_desc2"
    tkPowerupFrostOrbDesc3 = "powerup_frost_orb_desc3"
    tkPowerupArcaneOrbDesc1 = "powerup_arcane_orb_desc1"
    tkPowerupArcaneOrbDesc2 = "powerup_arcane_orb_desc2"
    tkPowerupArcaneOrbDesc3 = "powerup_arcane_orb_desc3"
    tkPowerupArcaneBulletsDesc1 = "powerup_arcane_bullets_desc1"
    tkPowerupArcaneBulletsDesc2 = "powerup_arcane_bullets_desc2"
    tkPowerupArcaneBulletsDesc3 = "powerup_arcane_bullets_desc3"
    tkPowerupArcaneAuraDesc1 = "powerup_arcane_aura_desc1"
    tkPowerupArcaneAuraDesc2 = "powerup_arcane_aura_desc2"
    tkPowerupArcaneAuraDesc3 = "powerup_arcane_aura_desc3"
    tkPowerupFireMasteryDesc = "powerup_fire_mastery_desc"
    tkPowerupPoisonMasteryDesc = "powerup_poison_mastery_desc"
    tkPowerupFrostMasteryDesc = "powerup_frost_mastery_desc"
    tkPowerupArcaneMasteryDesc = "powerup_arcane_mastery_desc"
    tkPowerupLightningMasteryDesc = "powerup_lightning_mastery_desc"
    tkPowerupWindMasteryDesc = "powerup_wind_mastery_desc"
    tkPowerupParryDesc = "powerup_parry_desc"
    tkPowerupBloodOrbDesc1 = "powerup_blood_orb_desc1"
    tkPowerupBloodOrbDesc2 = "powerup_blood_orb_desc2"
    tkPowerupBloodOrbDesc3 = "powerup_blood_orb_desc3"
    tkPowerupBloodAuraDesc1 = "powerup_blood_aura_desc1"
    tkPowerupBloodAuraDesc2 = "powerup_blood_aura_desc2"
    tkPowerupBloodAuraDesc3 = "powerup_blood_aura_desc3"
    tkPowerupBloodMasteryDesc = "powerup_blood_mastery_desc"
    tkPowerupRadialBurstDesc1 = "powerup_radial_burst_desc1"
    tkPowerupRadialBurstDesc2 = "powerup_radial_burst_desc2"
    tkPowerupRadialBurstDesc3 = "powerup_radial_burst_desc3"
    tkPowerupWallTurretsDesc1 = "powerup_wall_turrets_desc1"
    tkPowerupWallTurretsDesc2 = "powerup_wall_turrets_desc2"
    tkPowerupWallTurretsDesc3 = "powerup_wall_turrets_desc3"
    tkPowerupPulseArmorDesc1 = "powerup_pulse_armor_desc1"
    tkPowerupPulseArmorDesc2 = "powerup_pulse_armor_desc2"
    tkPowerupPulseArmorDesc3 = "powerup_pulse_armor_desc3"
    tkPowerupHeavyRoundsDesc1 = "powerup_heavy_rounds_desc1"
    tkPowerupHeavyRoundsDesc2 = "powerup_heavy_rounds_desc2"
    tkPowerupHeavyRoundsDesc3 = "powerup_heavy_rounds_desc3"
    tkPowerupFortifiedDesc1 = "powerup_fortified_desc1"
    tkPowerupFortifiedDesc2 = "powerup_fortified_desc2"
    tkPowerupFortifiedDesc3 = "powerup_fortified_desc3"
    tkPowerupSpecialRoundsDesc1 = "powerup_special_rounds_desc1"
    tkPowerupSpecialRoundsDesc2 = "powerup_special_rounds_desc2"
    tkPowerupSpecialRoundsDesc3 = "powerup_special_rounds_desc3"
    tkPowerupGiantSlayerDesc1 = "powerup_giant_slayer_desc1"
    tkPowerupGiantSlayerDesc2 = "powerup_giant_slayer_desc2"
    tkPowerupGiantSlayerDesc3 = "powerup_giant_slayer_desc3"
    tkPowerupCurseDesc1 = "powerup_curse_desc1"
    tkPowerupCurseDesc2 = "powerup_curse_desc2"
    tkPowerupCurseDesc3 = "powerup_curse_desc3"
    tkPowerupCelestialVeil = "powerup_celestial_veil"
    tkPowerupCelestialVeilDesc = "powerup_celestial_veil_desc"
    tkPowerupVolatile = "powerup_volatile"
    tkPowerupVolatileDesc = "powerup_volatile_desc"
    tkPowerupResonance = "powerup_resonance"
    tkPowerupResonanceDesc1 = "powerup_resonance_desc1"
    tkPowerupResonanceDesc2 = "powerup_resonance_desc2"
    tkPowerupResonanceDesc3 = "powerup_resonance_desc3"
    tkPowerupBloodPact = "powerup_blood_pact"
    tkPowerupBloodPactDesc = "powerup_blood_pact_desc"
    tkPowerupConduit = "powerup_conduit"
    tkPowerupConduitDesc = "powerup_conduit_desc"
    tkPowerupAftershock = "powerup_aftershock"
    tkPowerupAftershockDesc = "powerup_aftershock_desc"
    tkPowerupNova = "powerup_nova"
    tkPowerupNovaDesc = "powerup_nova_desc"
    tkPowerupHealPower = "powerup_heal_power"
    tkPowerupHealPowerDesc1 = "powerup_heal_power_desc1"
    tkPowerupHealPowerDesc2 = "powerup_heal_power_desc2"
    tkPowerupHealPowerDesc3 = "powerup_heal_power_desc3"
    tkPowerupBountiful = "powerup_bountiful"
    tkPowerupBountifulDesc = "powerup_bountiful_desc"

    # Player Feedback
    tkPlayerDodge = "player_dodge"
    tkPlayerParry = "player_parry"
    tkPlayerPhase = "player_phase"
    tkPlayerVeil = "player_veil"
    tkPlayerBloodPact = "player_blood_pact"
    tkPlayerConduit = "player_conduit"
    tkPlayerAftershock = "player_aftershock"
    tkPlayerNova = "player_nova"
    tkPlayerNovaCooldown = "player_nova_cooldown"
    tkPlayerAbilityOnCooldown = "player_ability_on_cooldown"

    # System Messages
    tkSystemDefensiveProcesses = "system_defensive_processes"
    tkSystemPressAnyKey = "system_press_any_key"
    tkBiosFastBoot = "bios_fast_boot"
    tkSystemNoStatistics = "system_no_statistics"
    tkSystemPressESCToReturn = "system_press_esc_to_return"

    # Loading Screen
    tkLoadingTitle = "loading_title"
    tkLoadingSubtitle = "loading_subtitle"
    tkLoadingInitializing = "loading_initializing"
    tkLoadingGeneratingSound = "loading_generating_sound"
    tkLoadingGeneratingMusic = "loading_generating_music"
    tkLoadingComplete = "loading_complete"
    tkLoadingHint = "loading_hint"
    tkLoadingCached = "loading_cached"

    # Cheat Menu Buttons
    tkCheatCloseInstruction = "cheat_close_instruction"
    tkCheatShowingItems = "cheat_showing_items"
    tkCheatScrollUp = "cheat_scroll_up"
    tkCheatScrollDown = "cheat_scroll_down"
    tkCheatNoPowerUpsSelected = "cheat_no_power_ups_selected"

    # OS Task Manager / System Monitoring
    tkOSRunningProcesses = "os_running_processes"
    tkOSNoActiveProcesses = "os_no_active_processes"
    tkOSProcessName = "os_process_name"
    tkOSVersion = "os_version"
    tkOSStatus = "os_status"
    tkOSSystemPerformance = "os_system_performance"
    tkOSSystemManager = "os_system_manager"
    tkOSSystemPaused = "os_system_paused"
    tkOSPressSpaceContinue = "os_press_space_continue"

    # OS Desktop / System Info
    tkOSSystemMonitor = "os_system_monitor"
    tkOSCPUIdle = "os_cpu_idle"
    tkOSMemory = "os_memory"
    tkOSNetwork = "os_network"
    tkOSTopHatOS = "os_tophat_os"
    tkOSEdition = "os_edition"
    tkOSTopHatButton = "os_tophat_button"
    tkOSNetIndicator = "os_net_indicator"

    # Stats Labels
    tkStatsSystemAnalytics = "stats_system_analytics"
    tkStatsRunReport = "stats_run_report"
    tkStatsWaveLabel = "stats_wave_label"
    tkStatsTimeLabel = "stats_time_label"
    tkStatsKillsLabel = "stats_kills_label"
    tkStatsAccuracyLabel = "stats_accuracy_label"
    tkStatsAvgDPS = "stats_avg_dps"

    # Enemy Labels
    tkEnemyActiveThreats = "enemy_active_threats"

    # PvP Lobby
    tkPvPTitle = "pvp_title"
    tkPvPHostGame = "pvp_host_game"
    tkPvPJoinGame = "pvp_join_game"
    tkPvPConfigureHosting = "pvp_configure_hosting"
    tkPvPNickname = "pvp_nickname"
    tkPvPMaxPlayers = "pvp_max_players"
    tkPvPShowIPs = "pvp_show_ips"
    tkPvPEnableInterpolation = "pvp_enable_interpolation"
    tkPvPTeamsMode = "pvp_teams_mode"
    tkPvPEnableTeams = "pvp_enable_teams"
    tkPvPNumTeams = "pvp_num_teams"
    tkPvPStartHosting = "pvp_start_hosting"
    tkPvPHostingGame = "pvp_hosting_game"
    tkPvPLocalIP = "pvp_local_ip"
    tkPvPPort = "pvp_port"
    tkPvPPlayersCount = "pvp_players_count"
    tkPvPClickAssignTeam = "pvp_click_assign_team"
    tkPvPYouHost = "pvp_you_host"
    tkPvPConnectedPlayers = "pvp_connected_players"
    tkPvPTeamsEnabled = "pvp_teams_enabled"
    tkPvPShowIP = "pvp_show_ip"
    tkPvPJoinGameTitle = "pvp_join_game_title"
    tkPvPHostIP = "pvp_host_ip"
    tkPvPClickCycleTabs = "pvp_click_cycle_tabs"
    tkPvPConnect = "pvp_connect"
    tkPvPConnecting = "pvp_connecting"
    tkPvPPleaseWait = "pvp_please_wait"
    tkPvPTimeoutIn = "pvp_timeout_in"
    tkPvPGameLobby = "pvp_game_lobby"
    tkPvPConnectedLabel = "pvp_connected_label"
    tkPvPClickBadgeTeam = "pvp_click_badge_team"
    tkPvPYou = "pvp_you"
    tkPvPStartGame = "pvp_start_game"
    tkPvPNeed2Players = "pvp_need_2_players"
    tkPvPConnected = "pvp_connected"
    tkPvPWaitingForHost = "pvp_waiting_for_host"
    tkPvPPlayersInLobby = "pvp_players_in_lobby"
    tkPvPConnectionError = "pvp_connection_error"
    tkPvPBack = "pvp_back"
    tkPvPPlayerNum = "pvp_player_num"
    tkPvPFailedStartHost = "pvp_failed_start_host"
    tkPvPFailedConnect = "pvp_failed_connect"
    tkPvPConnectionTimeout = "pvp_connection_timeout"
    tkPvPHostDisconnected = "pvp_host_disconnected"

    # PvP Config - Game Stats section
    tkPvPGameStats = "pvp_game_stats"
    tkPvPStatHp = "pvp_stat_hp"
    tkPvPStatKillLimit = "pvp_stat_kill_limit"
    tkPvPStatRespawn = "pvp_stat_respawn"
    tkPvPStatSpeed = "pvp_stat_speed"
    tkPvPStatDamage = "pvp_stat_damage"
    tkPvPStatFireRate = "pvp_stat_fire_rate"
    tkPvPStatBulletSpeed = "pvp_stat_bullet_speed"
    tkPvPStatBulletRadius = "pvp_stat_bullet_radius"
    tkPvPStatStartWalls = "pvp_stat_start_walls"
    tkPvPStatTimeLimit = "pvp_stat_time_limit"
    tkPvPStatNetQuality = "pvp_stat_net_quality"
    tkPvPNetQualityUltra = "pvp_net_quality_ultra"
    tkPvPNetQualityHigh = "pvp_net_quality_high"
    tkPvPNetQualityMedium = "pvp_net_quality_medium"
    tkPvPNetQualityLow = "pvp_net_quality_low"
    tkPvPValueOff = "pvp_value_off"
    tkPvPLocalNetMultiplayer = "pvp_local_net_multiplayer"
    tkPvPShareIPInfo = "pvp_share_ip_info"

    # PvP Teams
    tkPvPTeamRed = "pvp_team_red"
    tkPvPTeamBlue = "pvp_team_blue"
    tkPvPTeamGreen = "pvp_team_green"
    tkPvPTeamYellow = "pvp_team_yellow"
    tkPvPTeamOrange = "pvp_team_orange"
    tkPvPTeamPurple = "pvp_team_purple"
    tkPvPTeamNone = "pvp_team_none"

    # Play Styles
    tkStatsPlayStyleAggressive = "stats_play_style_aggressive"
    tkStatsPlayStyleDefensive = "stats_play_style_defensive"
    tkStatsPlayStyleMobile = "stats_play_style_mobile"
    tkStatsPlayStyleTank = "stats_play_style_tank"

    tkStatsNoPowerUpsSelected = "stats_no_powerups_selected"
    tkStatsNoGraphDataShort = "stats_no_graph_data_short"
    tkStatsControlsFooter = "stats_controls_footer"

    # Lifetime Stats Labels
    tkStatsMovementLabel = "stats_movement_label"
    tkStatsDistanceLabel = "stats_distance_label"
    tkStatsPhaseShiftsLabel = "stats_phase_shifts_label"
    tkStatsTimeWarpsLabel = "stats_time_warps_label"
    tkStatsNearDeathsLabel = "stats_near_deaths_label"
    tkStatsBestStreakLabel = "stats_best_streak_label"
    tkStatsTimeLowHPLabel = "stats_time_low_hp_label"
    tkStatsPerformanceLabel = "stats_performance_label"
    tkStatsPeakDPSLabel = "stats_peak_dps_label"
    tkStatsAvgDPSLabel = "stats_avg_dps_label"
    tkStatsKillsMinLabel = "stats_kills_min_label"
    tkStatsAvgWaveLabel = "stats_avg_wave_label"
    tkStatsFastWaveLabel = "stats_fast_wave_label"
    tkStatsResourcesLabel = "stats_resources_label"
    tkStatsCoinsEarnedLabel = "stats_coins_earned_label"
    tkStatsCoinsSpentLabel = "stats_coins_spent_label"
    tkStatsCoinsSavedLabel = "stats_coins_saved_label"
    tkStatsWallsPlacedLabel = "stats_walls_placed_label"
    tkStatsConsumablesLabel = "stats_consumables_label"
    tkStatsShopPurchasesLabel = "stats_shop_purchases_label"
    tkStatsPlayStyleLabel = "stats_play_style_label"
    tkStatsAggressionLabel = "stats_aggression_label"
    tkStatsCautionLabel = "stats_caution_label"
    tkStatsDPSOverTimeLabel = "stats_dps_over_time_label"

    # General
    tkYes = "general_yes"
    tkNo = "general_no"
    tkBack = "general_back"
    tkConfirm = "general_confirm"
    tkCancel = "general_cancel"

    # Exit Confirm Dialog
    tkConfirmQuitTitle = "confirm_quit_title"
    tkConfirmExitTitle = "confirm_exit_title"
    tkConfirmQuitBody = "confirm_quit_body"
    tkConfirmExitBody = "confirm_exit_body"
    tkConfirmUnsaved = "confirm_unsaved"
    tkConfirmCancelBtn = "confirm_cancel_btn"
    tkConfirmQuitBtn = "confirm_quit_btn"
    tkConfirmExitBtn = "confirm_exit_btn"
    tkConfirmCheckpointTitle = "confirm_checkpoint_title"
    tkConfirmCheckpointRestartBody = "confirm_checkpoint_restart_body"
    tkConfirmCheckpointSub = "confirm_checkpoint_sub"
    tkConfirmRestartBtn = "confirm_restart_btn"

    # Wave Celebration (d_enhancements)
    tkWaveClearedText = "wave_cleared_text"
    tkBossDefeatedText = "boss_defeated_text"
    tkWaveCelebKills = "wave_celeb_kills"
    tkWaveCelebAccuracy = "wave_celeb_accuracy"
    tkWaveCelebTime = "wave_celeb_time"
    tkWaveCelebCoins = "wave_celeb_coins"
    tkWaveCelebMaxCombo = "wave_celeb_max_combo"

    # Real-time stats overlay (d_enhancements)
    tkRealStatsPower = "real_stats_power"
    tkRealStatsDPS = "real_stats_dps"
    tkRealStatsKills = "real_stats_kills"
    tkRealStatsCPM = "real_stats_cpm"

    # Combo display (d_visuals)
    tkComboInsane = "combo_insane"
    tkComboCrazy = "combo_crazy"
    tkComboSick = "combo_sick"
    tkComboLabel = "combo_label"
    tkComboPerfectWave = "combo_perfect_wave"
    tkComboPerfectStreak = "combo_perfect_streak"
    tkComboCoins = "combo_coins"

    # Micro-reward popups & wave-stats
    tkMassacreBonus = "massacre_bonus"
    tkWaveStatsFlawless = "wave_stats_flawless"
    tkWaveStatsTitle = "wave_stats_title"
    tkWaveStatsKillsLabel = "wave_stats_kills_label"
    tkWaveStatsTimeLabel = "wave_stats_time_label"

    # 3D Boss Game HUD
    tkGame3DHp = "game3d_hp"
    tkGame3DAmmo = "game3d_ammo"
    tkGame3DBossHp = "game3d_boss_hp"
    tkGame3DPhase = "game3d_phase"
    tkGame3DSatellites = "game3d_satellites"
    tkGame3DDestroyAll = "game3d_destroy_all"
    tkGame3DPhaseTransition = "game3d_phase_transition"
    tkGame3DPaused = "game3d_paused"
    tkGame3DPressEscResume = "game3d_press_esc_resume"

    # OS UI
    tkOSRootPrompt = "os_root_prompt"
    tkOSLoading = "os_loading"
    tkOSShopNavigate = "os_shop_navigate"
    tkOSShopSelect = "os_shop_select"
    tkOSShopExit = "os_shop_exit"
    tkShopAvailableBalance = "shop_available_balance"

    # Gamemode Names and Descriptions
    tkGameModeWaveBased = "gamemode_wave_based_name"
    tkGameModeWaveBasedDesc = "gamemode_wave_based_desc"
    tkGameModeTimeSurvival = "gamemode_time_survival_name"
    tkGameModeTimeSurvivalDesc = "gamemode_time_survival_desc"
    tkGameModeSandbox = "gamemode_sandbox_name"
    tkGameModeSandboxDesc = "gamemode_sandbox_desc"
    tkGameModePvP = "gamemode_pvp_name"
    tkGameModePvPDesc = "gamemode_pvp_desc"

    # Enemy Names and Descriptions
    tkEnemyCircleName = "enemy_circle_name"
    tkEnemyCircleDesc = "enemy_circle_desc"
    tkEnemyPentagonName = "enemy_pentagon_name"
    tkEnemyPentagonDesc = "enemy_pentagon_desc"
    tkEnemyTriangleName = "enemy_triangle_name"
    tkEnemyTriangleDesc = "enemy_triangle_desc"
    tkEnemyStarName = "enemy_star_name"
    tkEnemyStarDesc = "enemy_star_desc"
    tkEnemyCubeName = "enemy_cube_name"
    tkEnemyCubeDesc = "enemy_cube_desc"
    tkEnemyHexagonName = "enemy_hexagon_name"
    tkEnemyHexagonDesc = "enemy_hexagon_desc"
    tkEnemyCrossName = "enemy_cross_name"
    tkEnemyCrossDesc = "enemy_cross_desc"
    tkEnemyDiamondName = "enemy_diamond_name"
    tkEnemyDiamondDesc = "enemy_diamond_desc"
    tkEnemyOctagonName = "enemy_octagon_name"
    tkEnemyOctagonDesc = "enemy_octagon_desc"
    tkEnemyTricksterName = "enemy_trickster_name"
    tkEnemyTricksterDesc = "enemy_trickster_desc"
    tkEnemyPhantomName = "enemy_phantom_name"
    tkEnemyPhantomDesc = "enemy_phantom_desc"
    tkEnemySniperName = "enemy_sniper_name"
    tkEnemySniperDesc = "enemy_sniper_desc"
    tkEnemyMageName = "enemy_mage_name"
    tkEnemyMageDesc = "enemy_mage_desc"

    # Boss Names and Descriptions
    tkBoss1Name = "boss_1_name"
    tkBoss1Desc = "boss_1_desc"
    tkBoss2Name = "boss_2_name"
    tkBoss2Desc = "boss_2_desc"
    tkBoss3Name = "boss_3_name"
    tkBoss3Desc = "boss_3_desc"
    tkBoss4Name = "boss_4_name"
    tkBoss4Desc = "boss_4_desc"
    tkBoss5Name = "boss_5_name"
    tkBoss5Desc = "boss_5_desc"
    tkBoss6Name = "boss_6_name"
    tkBoss6Desc = "boss_6_desc"
    tkBoss7Name = "boss_7_name"
    tkBoss7Desc = "boss_7_desc"
    tkBoss8Name = "boss_8_name"
    tkBoss8Desc = "boss_8_desc"
    tkBoss9Name = "boss_9_name"
    tkBoss9Desc = "boss_9_desc"
    tkBoss10Name = "boss_10_name"
    tkBoss10Desc = "boss_10_desc"
    tkBoss11Name = "boss_11_name"
    tkBoss11Desc = "boss_11_desc"
    tkBoss12Name = "boss_12_name"
    tkBoss12Desc = "boss_12_desc"

    # Common
    tkCommonOn = "common_on"
    tkCommonOff = "common_off"

    # Boss threat HUD
    tkBossThreatCritical = "boss_threat_critical"
    tkBossThreatPhaseHeader = "boss_threat_phase_header"
    tkBossThreatPhaseName = "boss_threat_phase_name"
    tkBossThreatBreached = "boss_threat_breached"
    tkBossThreatLocked = "boss_threat_locked"
    tkBossPhaseFirewall = "boss_phase_firewall"
    tkEnemySealedClearAdds = "enemy_sealed_clear_adds"
    tkEnemyOverloadHoldFire = "enemy_overload_hold_fire"

    # Sandbox power-up visuals tab
    tkSandboxPowerupVisuals = "sandbox_powerup_visuals"
    tkSandboxVisualsSubtitle = "sandbox_visuals_subtitle"
    tkSandboxBadgeLegendary = "sandbox_badge_legendary"
    tkSandboxBadgeCommon = "sandbox_badge_common"
    tkSandboxLv1Preview = "sandbox_lv1_preview"
    tkSandboxBadgeLocked = "sandbox_badge_locked"
    tkSandboxPowerupLockedName = "sandbox_powerup_locked_name"
    tkSandboxPowerupLockedDesc = "sandbox_powerup_locked_desc"
    tkSandboxEnterBoss3d = "sandbox_enter_boss_3d"
    tkSandboxTest3dArena = "sandbox_test_3d_arena"

    # Sandbox setup screen
    tkSandboxSetupTitle = "sandbox_setup_title"
    tkSandboxSetupSubtitle = "sandbox_setup_subtitle"
    tkSandboxStatMaxHp = "sandbox_stat_max_hp"
    tkSandboxStatDamage = "sandbox_stat_damage"
    tkSandboxStatFireRate = "sandbox_stat_fire_rate"
    tkSandboxStatMoveSpeed = "sandbox_stat_move_speed"
    tkSandboxStatBulletSpeed = "sandbox_stat_bullet_speed"
    tkSandboxStatWalls = "sandbox_stat_walls"
    tkSandboxStatCoins = "sandbox_stat_coins"
    tkSandboxStatStartWave = "sandbox_stat_start_wave"
    tkSandboxPresets = "sandbox_presets"
    tkSandboxPresetFresh = "sandbox_preset_fresh"
    tkSandboxPresetEarly = "sandbox_preset_early"
    tkSandboxPresetMid = "sandbox_preset_mid"
    tkSandboxPresetLate = "sandbox_preset_late"
    tkSandboxPresetEnd = "sandbox_preset_end"
    tkSandboxPresetGlass = "sandbox_preset_glass"
    tkSandboxPresetTank = "sandbox_preset_tank"
    tkSandboxApplyWaveAvg = "sandbox_apply_wave_avg"
    tkSandboxStartRun = "sandbox_start_run"
    tkSandboxBack = "sandbox_back"
    tkSandboxCustomLoadout = "sandbox_custom_loadout"

    # Advancements window
    tkAdvControlTitle = "adv_control_title"
    tkAdvSyncDesc = "adv_sync_desc"
    tkAdvUnlockedCount = "adv_unlocked_count"
    tkAdvClaimedCount = "adv_claimed_count"
    tkAdvShardBalance = "adv_shard_balance"
    tkAdvClaimAll = "adv_claim_all"
    tkAdvAllClaimed = "adv_all_claimed"
    tkAdvCategories = "adv_categories"
    tkAdvDetail = "adv_detail"
    tkAdvProgress = "adv_progress"
    tkAdvStatus = "adv_status"
    tkAdvReward = "adv_reward"
    tkAdvUnlockedAt = "adv_unlocked_at"
    tkAdvRewardClaimed = "adv_reward_claimed"
    tkAdvClaimReward = "adv_claim_reward"
    tkAdvLockedBtn = "adv_locked_btn"
    tkAdvTierLegend = "adv_tier_legend"
    tkAdvCategoryLabel = "adv_category_label"

    # Stats window (untranslated leftovers)
    tkStatsHealingSources = "stats_healing_sources"
    tkStatsHealthConsumable = "stats_health_consumable"
    tkStatsNoHealingData = "stats_no_healing_data"
    tkStatsTotalEarned = "stats_total_earned"
    tkStatsAnalyticsReport = "stats_analytics_report"

    # Desktop
    tkDesktopNet = "desktop_net"
    tkDesktopAdvancementUnlocked = "desktop_advancement_unlocked"

    # Debug panel runtime stats (effect labels already exist above)
    tkDebugPanelDps = "debug_panel_dps"
    tkDebugPanelCmin = "debug_panel_cmin"
    tkDebugPanelAbilities = "debug_panel_abilities"

    # Cheat / debug menu (new keys, many already exist above)
    tkCheatLv = "cheat_lv"
    tkCheatRemove = "cheat_remove"
    tkCheatAlive = "cheat_alive"
    tkCheatOf = "cheat_of"
    tkCheatMoreEnemies = "cheat_more_enemies"
    tkCheatCustomBoss = "cheat_custom_boss"
    tkCheatEnemyEnvironment = "cheat_enemy_environment"
    tkCheatConsHealth = "cheat_cons_health"
    tkCheatConsCoin = "cheat_cons_coin"
    tkCheatConsShield = "cheat_cons_shield"
    tkCheatConsDamage = "cheat_cons_damage"
    tkCheatConsDoubleCoin = "cheat_cons_double_coin"
    tkCheatConsLifesteal = "cheat_cons_lifesteal"

    # Comeback mechanic
    tkComebackBonusActive = "comeback_bonus_active"
    tkComebackBonusUntil = "comeback_bonus_until"

    # Settings: replay mode intros
    tkSettingsReplayModeIntros = "settings_replay_mode_intros"

    # Mode intro cutscenes: wave-based
    tkModeIntroWaveTitle = "mode_intro_wave_title"
    tkModeIntroWaveRec1  = "mode_intro_wave_rec1"
    tkModeIntroWave1a    = "mode_intro_wave_1a"
    tkModeIntroWave1b    = "mode_intro_wave_1b"
    tkModeIntroWaveRec2  = "mode_intro_wave_rec2"
    tkModeIntroWave2a    = "mode_intro_wave_2a"
    tkModeIntroWave2b    = "mode_intro_wave_2b"

    # Mode intro cutscenes: time survival
    tkModeIntroSurvTitle = "mode_intro_surv_title"
    tkModeIntroSurvRec1  = "mode_intro_surv_rec1"
    tkModeIntroSurv1a    = "mode_intro_surv_1a"
    tkModeIntroSurv1b    = "mode_intro_surv_1b"
    tkModeIntroSurvRec2  = "mode_intro_surv_rec2"
    tkModeIntroSurv2a    = "mode_intro_surv_2a"
    tkModeIntroSurv2b    = "mode_intro_surv_2b"

    # Mode intro cutscenes: roguelite
    tkModeIntroRogueTitle = "mode_intro_rogue_title"
    tkModeIntroRogueRec1  = "mode_intro_rogue_rec1"
    tkModeIntroRogue1a    = "mode_intro_rogue_1a"
    tkModeIntroRogue1b    = "mode_intro_rogue_1b"
    tkModeIntroRogueRec2  = "mode_intro_rogue_rec2"
    tkModeIntroRogue2a    = "mode_intro_rogue_2a"
    tkModeIntroRogue2b    = "mode_intro_rogue_2b"

    # Mode intro cutscenes: sandbox
    tkModeIntroSandboxTitle = "mode_intro_sandbox_title"
    tkModeIntroSandboxRec1  = "mode_intro_sandbox_rec1"
    tkModeIntroSandbox1a    = "mode_intro_sandbox_1a"
    tkModeIntroSandbox1b    = "mode_intro_sandbox_1b"

    # Mode intro cutscenes: pvp
    tkModeIntroPvPTitle = "mode_intro_pvp_title"
    tkModeIntroPvPRec1  = "mode_intro_pvp_rec1"
    tkModeIntroPvP1a    = "mode_intro_pvp_1a"
    tkModeIntroPvP1b    = "mode_intro_pvp_1b"
    tkModeIntroPvPRec2  = "mode_intro_pvp_rec2"
    tkModeIntroPvP2a    = "mode_intro_pvp_2a"
    tkModeIntroPvP2b    = "mode_intro_pvp_2b"
    # Mode-exclusive power-up names
    tkPowerupGlitchField    = "powerup_glitch_field"
    tkPowerupTimeSurge      = "powerup_time_surge"
    tkPowerupLastStand      = "powerup_last_stand"
    tkPowerupRecursion      = "powerup_recursion"
    tkPowerupSectorProtocol = "powerup_sector_protocol"
    # Mode-exclusive power-up descriptions
    tkPowerupGlitchFieldDesc1   = "powerup_glitch_field_desc1"
    tkPowerupGlitchFieldDesc2   = "powerup_glitch_field_desc2"
    tkPowerupGlitchFieldDesc3   = "powerup_glitch_field_desc3"
    tkPowerupTimeSurgeDesc1     = "powerup_time_surge_desc1"
    tkPowerupTimeSurgeDesc2     = "powerup_time_surge_desc2"
    tkPowerupTimeSurgeDesc3     = "powerup_time_surge_desc3"
    tkPowerupLastStandDesc      = "powerup_last_stand_desc"
    tkPowerupRecursionDesc1     = "powerup_recursion_desc1"
    tkPowerupRecursionDesc2     = "powerup_recursion_desc2"
    tkPowerupRecursionDesc3     = "powerup_recursion_desc3"
    tkPowerupSectorProtocolDesc = "powerup_sector_protocol_desc"
    # Stage 5 survival-exclusive names
    tkPowerupCrisisMode         = "powerup_crisis_mode"
    tkPowerupAdaptiveFirewall   = "powerup_adaptive_firewall"
    tkPowerupLastTransmission   = "powerup_last_transmission"
    tkPowerupKillChain          = "powerup_kill_chain"
    # Stage 5 survival-exclusive descriptions
    tkPowerupCrisisModeDesc1        = "powerup_crisis_mode_desc1"
    tkPowerupCrisisModeDesc2        = "powerup_crisis_mode_desc2"
    tkPowerupCrisisModeDesc3        = "powerup_crisis_mode_desc3"
    tkPowerupAdaptiveFirewallDesc1  = "powerup_adaptive_firewall_desc1"
    tkPowerupAdaptiveFirewallDesc2  = "powerup_adaptive_firewall_desc2"
    tkPowerupAdaptiveFirewallDesc3  = "powerup_adaptive_firewall_desc3"
    tkPowerupLastTransmissionDesc1  = "powerup_last_transmission_desc1"
    tkPowerupLastTransmissionDesc2  = "powerup_last_transmission_desc2"
    tkPowerupLastTransmissionDesc3  = "powerup_last_transmission_desc3"
    tkPowerupKillChainDesc          = "powerup_kill_chain_desc"
    # Stage 5 roguelite-exclusive names
    tkPowerupCorruptedCore      = "powerup_corrupted_core"
    tkPowerupRoomEcho           = "powerup_room_echo"
    tkPowerupChainReaction      = "powerup_chain_reaction"
    tkPowerupKernelExploit      = "powerup_kernel_exploit"
    # Stage 5 roguelite-exclusive descriptions
    tkPowerupCorruptedCoreDesc1     = "powerup_corrupted_core_desc1"
    tkPowerupCorruptedCoreDesc2     = "powerup_corrupted_core_desc2"
    tkPowerupCorruptedCoreDesc3     = "powerup_corrupted_core_desc3"
    tkPowerupRoomEchoDesc1          = "powerup_room_echo_desc1"
    tkPowerupRoomEchoDesc2          = "powerup_room_echo_desc2"
    tkPowerupRoomEchoDesc3          = "powerup_room_echo_desc3"
    tkPowerupChainReactionDesc1     = "powerup_chain_reaction_desc1"
    tkPowerupChainReactionDesc2     = "powerup_chain_reaction_desc2"
    tkPowerupChainReactionDesc3     = "powerup_chain_reaction_desc3"
    tkPowerupKernelExploitDesc      = "powerup_kernel_exploit_desc"
    tkPowerupDataHarvest        = "powerup_data_harvest"
    tkPowerupDataHarvestDesc1       = "powerup_data_harvest_desc1"
    tkPowerupDataHarvestDesc2       = "powerup_data_harvest_desc2"
    tkPowerupDataHarvestDesc3       = "powerup_data_harvest_desc3"
    # Discovery banner
    tkNewProcessInstalled = "new_process_installed"

# Translation tables
var translations: Table[localization.Language, Table[system.string, system.string]] = {
  English: {
    # Main Menu
    "menu_play": "play",
    "menu_survival": "survival",
    "menu_stats": "stats",
    "menu_help": "help",
    "menu_settings": "settings",
    "menu_quit": "exit",
    "menu_sandbox": "sandbox",

    # Desktop icons
    "desktop_icon_play": "WAVE0.exe",
    "desktop_icon_survival": "LASTSTAND.exe",
    "desktop_icon_stats": "LOGS.dat",
    "desktop_icon_settings": "SETTINGS.sys",
    "desktop_icon_help": "MANUAL.exe",
    "desktop_icon_quit": "POWEROFF.exe",
    "desktop_icon_sandbox": "LAB.exe",
    "desktop_icon_shop": "CHROMA.db",
    "desktop_icon_pvp": "DUELINK.exe",
    "desktop_icon_roguelite": "ROOTMAP.db",
    "desktop_icon_advancements": "ASCEND.db",
    "desktop_icon_changelog": "PATCHLOG.txt",
    "desktop_icon_credits": "CREDITS.nfo",

    # Credits window
    "credits_window_title": "Credits - About",
    "credits_header": "Credits",
    "credits_role": "Design & Programming",
    "credits_built_with": "Built With",
    "credits_thanks": "Thanks",
    "credits_thanks_body": "Everyone who played, reported bugs and suggested ideas.",
    "credits_license": "Licensed under Apache 2.0",
    "support_title": "Support the Project",
    "support_blurb": "TopHat-ShooterOS is free and open source. Support is optional and never gates any feature.",
    "support_note": "Links open in your browser.",

    # Changelog window
    "changelog_window_title": "Patch Notes - Changelog",
    "changelog_header": "What's New",
    "changelog_since": "Changes since v5.5.2",
    "changelog_latest": "LATEST",
    "changelog_cat_new": "New",
    "changelog_cat_improved": "Improvements",
    "changelog_cat_balance": "Balance",
    "changelog_cat_fixed": "Fixes",

    # Settings
    "settings_title": "SETTINGS",
    "settings_fps_limit": "FPS Limit:",
    "settings_click_edit": "Click to edit, Enter to confirm",
    "settings_sound_effects": "Sound Effects:",
    "settings_music": "Music:",
    "settings_sound_effects_desc": "(explosions, UI, in-game effects)",
    "settings_music_desc": "(background music volume)",
    "settings_fullscreen": "Fullscreen:",
    "settings_fullscreen_toggle": "(Press F11 to toggle)",
    "settings_render_resolution": "Improved resolution (SSAA):",
    "settings_render_resolution_desc": "(improves fullscreen sharpness)",
    "settings_render_resolution_disabled": "Disabled",
    "settings_render_resolution_enabled": "Enabled",
    "settings_render_resolution_fullscreen_only": "Fullscreen Only",
    "settings_vsync": "VSync:",
    "settings_vsync_desc": "(locks FPS to monitor refresh rate)",
    "settings_show_fps": "Show FPS:",
    "settings_mouse_support": "Mouse Support:",
    "settings_mouse_support_desc": "(new menu navigation)",
    "settings_mouse_bonding": "Mouse Bonding:",
    "settings_mouse_bonding_desc": "(cycle mode with a click)",
    "settings_mouse_bonding_off": "Off",
    "settings_mouse_bonding_while_shooting": "While Shooting",
    "settings_mouse_bonding_always_in_game": "Always In-Game",
    "settings_mouse_bonding_always": "Always",
    "settings_show_cursor": "Show Cursor:",
    "settings_show_cursor_desc": "(visual only)",
    "settings_debug_panel": "Debug Panel:",
    "settings_debug_panel_desc": "(top-right stats)",
    "settings_arena_vignette": "Arena Vignette:",
    "settings_arena_vignette_desc": "(dark edge shading)",
    "settings_low_health_vignette": "Low HP Vignette:",
    "settings_low_health_vignette_desc": "(red warning when HP is low)",
    "settings_show_hints": "Show Hints:",
    "settings_show_hints_desc": "(E: Wall, ESC: Pause)",
    "settings_hud_layout": "HUD Layout:",
    "settings_hud_layout_desc": "(Widescreen adds side UI bands)",
    "settings_hud_layout_classic": "Classic (4:3)",
    "settings_hud_layout_widescreen": "Widescreen (16:9)",
    "settings_show_enemy_labels": "Show Enemy Labels:",
    "settings_show_enemy_labels_desc": "(name tags above enemies)",
    "settings_exit_confirm": "Exit Confirm:",
    "settings_exit_confirm_desc": "(prompt when quitting game)",
    "settings_language": "Language:",
    "settings_replay_intro": "Replay Intro",
    "settings_replay_ending": "Replay Ending",
    "settings_replay_roguelite_ending": "Replay Roguelite",
    "settings_replay_survival_ending": "Replay Survival",
    "settings_replay_wave_intro": "Wave Intro",
    "settings_replay_survival_intro": "Survival Intro",
    "settings_replay_roguelite_intro": "Roguelite Intro",
    "settings_replay_sandbox_intro": "Sandbox Intro",
    "settings_replay_pvp_intro": "PvP Intro",
    "settings_back_to_menu": "Press ESC to return to menu",

    "lore_title_card_sub": "ARCHIVE PLAYBACK // INCIDENT LOG",
    "lore_live": "LIVE",
    "lore_playback": "PLAY",
    "lore_controls_ff": "HOLD ENTER: X2  |  HOLD SPACE: SKIP",
    "lore_controls_ff_active": "HOLD ENTER: 2X ACTIVE  |  HOLD SPACE: SKIP",
    "lore_rec_breach": "REC 00: SYSTEM BREACH",
    "lore_rec_swarm": "REC 01: HOSTILE PROCESS FLOOD",
    "lore_rec_awaken": "REC 02: TOPHAT KERNEL WAKE",
    "lore_rec_boss": "REC 03: THE ROOT",
    "lore_rec_counter": "REC 04: DEFENSE LOOP",
    "lore_rec_directive": "REC 05: PROTOCOL HANDOFF",
    "lore_breach_1": "An unknown server forces the gate of TopHat-ShooterOS.",
    "lore_breach_2": "The gate is only a door. Something came through it.",
    "lore_swarm_1": "Its corruption pours in: shapes, shards, and hunger.",
    "lore_swarm_2": "Every wave learns. Every wave gets closer.",
    "lore_awaken_1": "TOPHAT wakes and boots its last trusted process - you.",
    "lore_awaken_2": "The kernel cannot fight while contained. You can.",
    "lore_boss_1": "What came through the breach is older than the OS.",
    "lore_boss_2": "It runs as root, and it writes every attack you face.",
    "lore_counter_1": "Your fire becomes patches. Its shards become power.",
    "lore_counter_2": "The system can still be saved.",
    "lore_directive_title": "DEFENSE PROTOCOL: ACTIVE",
    "lore_directive_sub": "Hold the line, operator.",

    "end_title_card_sub": "ARCHIVE PLAYBACK // INCIDENT RESOLVED",
    "end_rec_fall": "REC 06: THE ROOT PURGED",
    "end_rec_purge": "REC 07: MEMORY RECLAIMED",
    "end_rec_restore": "REC 08: KERNEL RESTORED",
    "end_rec_crown": "REC 09: ROOT ACCESS GRANTED",
    "end_rec_signoff": "REC 10: PROTOCOL COMPLETE",
    "end_fall_1": "The Root shatters.",
    "end_fall_2": "Its code unravels back through the breach it crawled from.",
    "end_purge_1": "The corruption recedes, sector by sector.",
    "end_purge_2": "Clean memory is reclaimed in its wake.",
    "end_restore_1": "TOPHAT kernel restored. Containment stable.",
    "end_restore_2": "Threat level dropping... zero.",
    "end_crown_1": "With the Root gone, its root access falls to you.",
    "end_crown_2": "You wear the crown of the kernel now.",
    "end_signoff_title": "SYSTEM SECURED",
    "end_signoff_sub": "Threat level zero. Stand down - you have earned the crown.",

    "rog_end_title_card_sub": "ARCHIVE PLAYBACK // DEEP RECOVERY",
    "rog_end_rec_descend": "DELVE 01: SECTOR DESCENT",
    "rog_end_rec_core": "DELVE 02: CORRUPTED CORE",
    "rog_end_rec_extract": "DELVE 03: DATA EXTRACTION",
    "rog_end_rec_reveal": "DELVE 04: ORIGIN EXPOSED",
    "rog_end_rec_ascend": "DELVE 05: STACK ASCENT",
    "rog_end_rec_signoff": "DELVE 06: SURFACE REACHED",
    "rog_end_descend_1": "The surface was secured, but the rot still pulsed below.",
    "rog_end_descend_2": "Crowned now, you descended to end it at the source.",
    "rog_end_core_1": "At the base of the recursion waited the seed-",
    "rog_end_core_2": "the core the Root grew from, older than TOPHAT itself.",
    "rog_end_extract_1": "You tore the seed free, shard by shard,",
    "rog_end_extract_2": "and the endless loop began to unwind.",
    "rog_end_reveal_1": "In the seed's last light you saw the truth:",
    "rog_end_reveal_2": "the breach did not bring the Root. It woke it.",
    "rog_end_ascend_1": "Up through the collapsing stack you climbed,",
    "rog_end_ascend_2": "recovered cores burning bright in hand.",
    "rog_end_signoff_title": "SECTOR CLEARED",
    "rog_end_signoff_sub": "The recursion is broken - but now you know how deep root goes.",

    "sur_end_title_card_sub": "ARCHIVE PLAYBACK // THE LONG WATCH",
    "sur_end_rec_watch": "LOG 01: THE LONG WATCH",
    "sur_end_rec_surge": "LOG 02: FINAL SURGE",
    "sur_end_rec_fall": "LOG 03: SIGNAL LOST",
    "sur_end_rec_shutdown": "LOG 04: SYSTEM HALTED",
    "sur_end_rec_signoff": "LOG 05: END OF ARCHIVE",
    "sur_end_watch_1": "Long after the Root, long after the crown, you kept the watch.",
    "sur_end_watch_2": "The flood never ended. It only waited.",
    "sur_end_surge_1": "But the flood never tired the way you did.",
    "sur_end_surge_2": "The last surge found the gap you couldn't close.",
    "sur_end_fall_1": "Your process dimmed, then went dark.",
    "sur_end_fall_2": "And this time, no reboot answered.",
    "sur_end_shutdown_1": "One by one, the kernel's lights went out.",
    "sur_end_shutdown_2": "TopHat-ShooterOS stopped responding.",
    "sur_end_signoff_title": "SYSTEM HALTED",
    "sur_end_signoff_sub": "The long watch is over. The screen stays dark.",

    "settings_section_data_management": "DATA MANAGEMENT",
    "settings_reset_all_data": "Reset All Data",
    "settings_reset_advancements": "Reset Advancements",
    "settings_reset_roguelite_data": "Reset Roguelite",
    "settings_confirm_reset": "Confirm Reset",
    "settings_reset_complete": "Reset complete",
    "settings_reset_failed": "Reset failed",

    # Settings window tabs and sections
    "settings_tab_graphics": "Graphics",
    "settings_tab_audio": "Audio",
    "settings_tab_controls": "Controls",
    "settings_tab_gameplay": "Gameplay",
    "settings_tab_cinematics": "Cinematics",

    "settings_section_story": "STORY CINEMATICS",
    "settings_section_mode_intros": "MODE INTROS",
    "settings_section_display": "DISPLAY",
    "settings_section_volume_control": "VOLUME CONTROL",
    "settings_section_input_method": "INPUT METHOD",
    "settings_section_assistance": "ASSISTANCE",
    "settings_section_localization": "LOCALIZATION",
    "settings_section_keyboard_shortcuts": "KEYBOARD SHORTCUTS",

    "settings_keyboard_wasd": "WASD / Arrows",
    "settings_keyboard_movement": "Movement",
    "settings_keyboard_mouse_space": "Mouse / Space",
    "settings_keyboard_shoot": "Shoot",
    "settings_keyboard_e": "E",
    "settings_keyboard_place_wall": "Place Wall",
    "settings_keyboard_q": "Q",
    "settings_keyboard_legendary_abilities": "Legendary Abilities",
    "settings_keyboard_esc": "ESC",
    "settings_keyboard_pause_menu": "Pause / Menu",
    "settings_keyboard_f11": "F11",
    "settings_keyboard_toggle_fullscreen": "Toggle Fullscreen",
    "settings_keyboard_tab": "Tab",

    # Rebindable keybinds UI (English)
    "settings_section_keybindings": "KEYBINDINGS",
    "keybind_move_up": "Move Up",
    "keybind_move_down": "Move Down",
    "keybind_move_left": "Move Left",
    "keybind_move_right": "Move Right",
    "keybind_shoot": "Shoot",
    "keybind_place_wall": "Place Wall / Interact",
    "keybind_legendary": "Legendary Ability",
    "keybind_press_any_key": "Press any key...",
    "keybind_reset_defaults": "Reset to Defaults",
    "keybind_non_rebindable_note": "ESC: Pause  |  F11: Fullscreen  (fixed)",
    "gamepad_column_key": "Key",
    "gamepad_column_pad": "Pad",
    "gamepad_press_any_button": "Press a button...",
    "gamepad_reserved_note": "Pad: A = click, B = back, Start = pause (fixed)",
    "settings_aim_assist": "Aim Assist",
    "settings_aim_assist_desc": "Gamepad aim snaps to nearby enemies",
    "settings_controller": "Controller",
    "settings_controller_desc": "Which detected gamepad controls the game",
    "settings_controller_auto": "Auto (first detected)",
    "settings_controller_none": "No controller detected",

    # Game UI
    "game_pause": "PAUSED",
    "game_resume": "Resume",
    "game_restart": "Restart",
    "game_main_menu": "Main Menu",
    "game_over": "GAME OVER",
    "game_score": "Score:",
    "game_wave": "Wave",
    "game_health": "Health:",
    "game_coins": "Coins:",
    "game_status": "STATUS",
    "game_wave_info": "Wave Info:",
    "game_active": "Active",
    "game_boss": "BOSS",
    "game_boss_fight": "BOSS FIGHT",
    "game_collect": "Collect",
    "game_left": "left",
    "game_charges": "Charges",
    "game_processes": "Processes",

    # Shop/Powerups
    "shop_title": "SHOP",
    "shop_buy": "Buy",
    "shop_upgrade": "Upgrade",
    "shop_cost": "Cost:",
    "shop_owned": "Owned",
    "shop_credit_store": "CREDIT STORE - UPGRADES AVAILABLE",
    "shop_upgrades_available": "UPGRADES AVAILABLE",
    "shop_active_upgrades": "ACTIVE UPGRADES",
    "shop_available_purchases": "AVAILABLE PURCHASES:",
    "shop_controls": "CONTROLS:",
    "shop_navigate": "Navigate",
    "shop_continue": "Continue",
    "shop_buy_selected": "BUY SELECTED",
    "shop_insufficient_credits": "INSUFFICIENT CREDITS",
    "shop_no_permanent": "No permanent upgrades yet.",
    "shop_defeat_waves": "Defeat waves to unlock!",
    "shop_credits": "CR",
    "shop_bought": "Bought",
    "shop_damage_plus": "Damage +",
    "shop_damage_plus_desc": "Bullet damage boost",
    "shop_fire_rate_plus": "Fire Rate +",
    "shop_fire_rate_plus_desc": "Fire rate boost",
    "shop_move_speed_plus": "Move Speed +",
    "shop_move_speed_plus_desc": "Movement speed boost",
    "shop_max_health_plus": "Max Health +",
    "shop_max_health_plus_desc": "Large max HP increase",
    "shop_bullet_speed_plus": "Bullet Speed +",
    "shop_bullet_speed_plus_desc": "Bullet velocity boost",
    "shop_wall_x4": "Wall (x10)",
    "shop_wall_x4_desc": "Buy 10 deployable walls",

    # Powerup Names
    "powerup_double_shot": "Double Shot",
    "powerup_rotating_shield": "Rotating Shield",
    "powerup_magical_bullets": "Magical Bullets",
    "powerup_piercing_shots": "Piercing Shots",
    "powerup_multi_shot": "Multi-Shot",
    "powerup_explosive_bullets": "Explosive Rounds",
    "powerup_life_steal": "Life Steal",
    "powerup_rapid_fire": "Overclock",
    "powerup_max_health": "Juggernaut",
    "powerup_speed_boost": "Momentum",
    "powerup_bullet_speed": "Lightspeed",
    "powerup_lucky_coins": "Greed",
    "powerup_wall_master": "Fortify",
    "powerup_regeneration": "Regeneration",
    "powerup_dodge_chance": "Evasion",
    "powerup_critical_hit": "Critical Strike",
    "powerup_blood_bullets": "Blood Bullets",
    "powerup_bullet_ricochet": "Ricochet",
    "powerup_slow_field": "Slow Field",
    "powerup_rage": "Rage",
    "powerup_berserker": "Berserker",
    "powerup_thorns": "Thorns",
    "powerup_bullet_split": "Split Shot",
    "powerup_chain_lightning": "Chain Lightning",
    "powerup_frost_shots": "Frost Shots",
    "powerup_poison_shot": "Poison Shots",
    "powerup_fire_bullets": "Fire Bullets",
    "powerup_wind_bullets": "Wind Bullets",
    "powerup_fire_aura": "Fire Aura",
    "powerup_lightning_aura": "Lightning Aura",
    "powerup_poison_aura": "Poison Aura",
    "powerup_wind_aura": "Wind Aura",
    "powerup_time_warp": "Chronos",
    "powerup_gravity_well": "Singularity",
    "powerup_phase_shift": "Phase Walker",
    "powerup_overcharge": "Momentum",
    "powerup_echo_shots": "Echo Strike",
    "powerup_rotating_orbs": "Elemental Orbs",
    "powerup_poison_orb": "Poison Orbs",
    "powerup_fire_orb": "Fire Orbs",
    "powerup_lightning_orb": "Lightning Orbs",
    "powerup_wind_orb": "Wind Orbs",
    "powerup_frost_orb": "Frost Orbs",
    "powerup_arcane_bullets": "Arcane Bullets",
    "powerup_arcane_aura": "Arcane Aura",
    "powerup_arcane_orb": "Arcane Orbs",
    "powerup_fire_mastery": "Inferno Mastery",
    "powerup_poison_mastery": "Toxic Overlord",
    "powerup_frost_mastery": "Frost King",
    "powerup_arcane_mastery": "Arcane Ascension",
    "powerup_lightning_mastery": "Storm Lord",
    "powerup_wind_mastery": "Wind Master",
    "powerup_parry": "Parry",
    "powerup_blood_orb": "Blood Orbs",
    "powerup_blood_aura": "Blood Aura",
    "powerup_blood_mastery": "Blood Lord",
    "powerup_radial_burst": "Radial Burst",
    "powerup_wall_turrets": "Wall Sentinels",
    "powerup_pulse_armor": "Pulse Armor",
    "powerup_heavy_rounds": "Heavy Rounds",
    "powerup_fortified": "Fortified",
    "powerup_special_rounds": "Special Rounds",
    "powerup_giant_slayer": "Giant Slayer",
    "powerup_curse": "Curse",
    "powerup_celestial_veil": "Celestial Veil",

    # Powerup Descriptions
    "powerup_double_shot_desc": "Fire additional burst after 0.08s (-15% dmg per bullet, -25% fire rate)",
    "powerup_rotating_shield_desc1": "3 shields (30% coverage, 100 HP, 6s respawn)",
    "powerup_rotating_shield_desc2": "3 shields (35% coverage, 250 HP, 5s respawn)",
    "powerup_rotating_shield_desc3": "3 shields (40% coverage, 400 HP, 3s respawn)",
    "powerup_magical_bullets_desc": "Bullets track nearest enemy",
    "powerup_piercing_shots_desc1": "Bullets pierce 1 enemy (-33% damage per pierce)",
    "powerup_piercing_shots_desc2": "Bullets pierce 2 enemies (-33% damage per pierce)",
    "powerup_piercing_shots_desc3": "Bullets pierce 3 enemies (-33% damage per pierce)",
    "powerup_multi_shot_desc": "Shoot in 3 directions (-30% dmg per bullet)",
    "powerup_explosive_bullets_desc1": "Bullets explode (50% bullet dmg, small radius)",
    "powerup_explosive_bullets_desc2": "Bullets explode (50% bullet dmg, medium radius)",
    "powerup_explosive_bullets_desc3": "Bullets explode (50% bullet dmg, large radius)",
    "powerup_life_steal_desc1": "Heal 100 HP per 10 kills",
    "powerup_life_steal_desc2": "Heal 100 HP per 7 kills",
    "powerup_life_steal_desc3": "Heal 100 HP per 5 kills",
    "powerup_rapid_fire_desc": "Spin-up: hold fire to ramp fire rate up to +30% faster",
    "powerup_max_health_desc": "Juggernaut: +2% damage per 100 max HP, including base HP (up to +40%)",
    "powerup_speed_boost_desc": "Momentum: deal up to +25% damage while moving",
    "powerup_bullet_speed_desc": "Lightspeed: each shot fires an instant tracer beam that hits the first enemy in line for 50% damage",
    "powerup_lucky_coins_desc": "Doubles all coins collected",
    "powerup_wall_master_desc": "Walls have +250% HP turrets have +100% damage",
    "powerup_regeneration_desc1": "Regen 150 HP + 3% max HP per wave",
    "powerup_regeneration_desc2": "Regen 250 HP + 5% max HP per wave",
    "powerup_regeneration_desc3": "Regen 350 HP + 7% max HP per wave",
    "powerup_dodge_chance_desc1": "15% chance to dodge hits",
    "powerup_dodge_chance_desc2": "20% chance to dodge hits",
    "powerup_dodge_chance_desc3": "30% chance to dodge hits",
    "powerup_critical_hit_desc1": "20% chance for 2x damage (all sources)",
    "powerup_critical_hit_desc2": "35% chance for 2x damage (all sources)",
    "powerup_critical_hit_desc3": "50% chance for 2x damage (all sources)",
    "powerup_blood_bullets_desc1": "Heal 1 HP + 0.75% of bullet damage (blood)",
    "powerup_blood_bullets_desc2": "Heal 1 HP + 1% of bullet damage (blood)",
    "powerup_blood_bullets_desc3": "Heal 1 HP + 1.375% of bullet damage (blood)",
    "powerup_bullet_ricochet_desc1": "Bullets ricochet once (50% damage per ricochet)",
    "powerup_bullet_ricochet_desc2": "Bullets ricochet twice (50% damage per ricochet)",
    "powerup_bullet_ricochet_desc3": "Bullets ricochet 3 times (50% damage per ricochet)",
    "powerup_slow_field_desc1": "Pulse: slow enemies 30% in 288 radius",
    "powerup_slow_field_desc2": "Pulse: slow enemies 45% in 374 radius",
    "powerup_slow_field_desc3": "Pulse: slow enemies 55% in 460 radius",
    "powerup_rage_desc1": "+5% dmg per 10% HP lost",
    "powerup_rage_desc2": "+8% dmg per 10% HP lost",
    "powerup_rage_desc3": "+12% dmg per 10% HP lost",
    "powerup_berserker_desc1": "+5% fire rate per 10% HP lost",
    "powerup_berserker_desc2": "+8% fire rate per 10% HP lost",
    "powerup_berserker_desc3": "+12% fire rate per 10% HP lost",
    "powerup_thorns_desc1": "Reflect 100% damage to attacker",
    "powerup_thorns_desc2": "Reflect 200% damage to attacker",
    "powerup_thorns_desc3": "Reflect 300% damage to attacker",
    "powerup_bullet_split_desc1": "Bullets split into 2 damage-only fragments",
    "powerup_bullet_split_desc2": "Bullets split into 3 damage-only fragments",
    "powerup_bullet_split_desc3": "Bullets split into 4 damage-only fragments",
    "powerup_chain_lightning_desc1": "Hit chains to 1 enemy (70% bullet dmg, 120 range, 0.05s stun)",
    "powerup_chain_lightning_desc2": "Hit chains to 2 enemies (85% bullet dmg, 140 range, 0.05s stun)",
    "powerup_chain_lightning_desc3": "Hit chains to 3 enemies (100% bullet dmg, 160 range, 0.05s stun)",
    "powerup_frost_shots_desc1": "Bullets slow enemies 25% (permanent)",
    "powerup_frost_shots_desc2": "Bullets slow enemies 40% (permanent)",
    "powerup_frost_shots_desc3": "Bullets slow enemies 60% (permanent)",
    "powerup_poison_shot_desc1": "Bullets poison ({0}, 4s, stacks over time)",
    "powerup_poison_shot_desc2": "Bullets poison ({0}, 5s, stacks over time)",
    "powerup_poison_shot_desc3": "Bullets poison ({0}, 6s, stacks over time)",
    "powerup_fire_bullets_desc1": "Bullets burn ({0}, 2s)",
    "powerup_fire_bullets_desc2": "Bullets burn ({0}, 3s)",
    "powerup_fire_bullets_desc3": "Bullets burn ({0}, 4s)",
    "powerup_wind_bullets_desc1": "Bullets knock back enemies (weak push, +50 damage)",
    "powerup_wind_bullets_desc2": "Bullets knock back enemies (medium push, +50 damage)",
    "powerup_wind_bullets_desc3": "Bullets knock back enemies (strong push, +50 damage)",
    "powerup_fire_aura_desc1": "Pulse-burn enemies {0} in 238 radius (2s)",
    "powerup_fire_aura_desc2": "Pulse-burn enemies {0} in 309 radius (3s)",
    "powerup_fire_aura_desc3": "Pulse-burn enemies {0} in 380 radius (4s)",
    "powerup_lightning_aura_desc1": "Arc storm {0} in 223 radius (chains 1x)",
    "powerup_lightning_aura_desc2": "Arc storm {0} in 289 radius (chains 2x)",
    "powerup_lightning_aura_desc3": "Arc storm {0} in 356 radius (chains 3x)",
    "powerup_poison_aura_desc1": "Pulse-poison {0} in 253 radius (6s, stacks over time)",
    "powerup_poison_aura_desc2": "Pulse-poison {0} in 328 radius (8s, stacks over time)",
    "powerup_poison_aura_desc3": "Pulse-poison {0} in 404 radius (10s, stacks over time)",
    "powerup_wind_aura_desc1": "Gust every 3s: blast enemies away in 270 radius",
    "powerup_wind_aura_desc2": "Gust every 2.6s: blast enemies away in 351 radius",
    "powerup_wind_aura_desc3": "Gust every 2.2s: blast enemies away in 432 radius",
    "powerup_time_warp_desc": "Slow time 50% for 3.5s (2 uses/wave, 10s cd)",
    "powerup_gravity_well_desc": "Pull enemies in 300 radius. grants a 10% HP shield (5s delay to regen, regens 5%/s)",
    "powerup_phase_shift_desc": "Dash forward (5s cd, 0.5s invuln, scales with speed)",
    "powerup_overcharge_desc": "Bullets deal +10% dmg per 100 units traveled (max 150%, reaches at 1000 units)",
    "powerup_echo_shots_desc": "Bullets leave ghost trail (25% dmg)",
    "powerup_rotating_orbs_desc": "All 6 elemental orbs ({0} dmg/hit)",
    "powerup_poison_orb_desc1": "4 poison orbs ({0} dmg/hit)",
    "powerup_poison_orb_desc2": "8 poison orbs ({0} dmg/hit)",
    "powerup_poison_orb_desc3": "12 poison orbs ({0} dmg/hit)",
    "powerup_fire_orb_desc1": "4 fire orbs ({0} dmg/hit)",
    "powerup_fire_orb_desc2": "8 fire orbs ({0} dmg/hit)",
    "powerup_fire_orb_desc3": "12 fire orbs ({0} dmg/hit)",
    "powerup_lightning_orb_desc1": "4 lightning orbs ({0} dmg/hit)",
    "powerup_lightning_orb_desc2": "8 lightning orbs ({0} dmg/hit)",
    "powerup_lightning_orb_desc3": "12 lightning orbs ({0} dmg/hit)",
    "powerup_wind_orb_desc1": "4 wind orbs, push enemies ({0} dmg/hit)",
    "powerup_wind_orb_desc2": "8 wind orbs, push enemies ({0} dmg/hit)",
    "powerup_wind_orb_desc3": "12 wind orbs, push enemies ({0} dmg/hit)",
    "powerup_frost_orb_desc1": "4 frost orbs, slow enemies ({0} dmg/hit)",
    "powerup_frost_orb_desc2": "8 frost orbs, slow enemies ({0} dmg/hit)",
    "powerup_frost_orb_desc3": "12 frost orbs, slow enemies ({0} dmg/hit)",
    "powerup_arcane_orb_desc1": "4 arcane orbs ({0} dmg/hit)",
    "powerup_arcane_orb_desc2": "8 arcane orbs ({0} dmg/hit)",
    "powerup_arcane_orb_desc3": "12 arcane orbs ({0} dmg/hit)",
    "powerup_arcane_bullets_desc1": "Bullets enhanced with arcane power (+20% bullet damage, arcane)",
    "powerup_arcane_bullets_desc2": "Bullets enhanced with arcane power (+40% bullet damage, arcane)",
    "powerup_arcane_bullets_desc3": "Bullets enhanced with arcane power (+60% bullet damage, arcane)",
    "powerup_arcane_aura_desc1": "Arcane pulse {0} in 200 radius, arcane",
    "powerup_arcane_aura_desc2": "Arcane pulse {0} in 260 radius, arcane",
    "powerup_arcane_aura_desc3": "Arcane pulse {0} in 320 radius, arcane",
    "powerup_fire_mastery_desc": "Fire effects: +150% dmg, +50% duration, +45% slow",
    "powerup_poison_mastery_desc": "Poison effects: +150% dmg, +200% duration, +40% slow",
    "powerup_frost_mastery_desc": "Frost effects: +25% slow (up to 85%), orbs chill 55%",
    "powerup_arcane_mastery_desc": "Arcane effects: +75% dmg, bullets also pierce",
    "powerup_lightning_mastery_desc": "Lightning effects: +150% dmg, +25% slow, +1 chain, +50% range",
    "powerup_wind_mastery_desc": "Wind effects: +150% dmg, +45% slow, 3.5x push",
    "powerup_parry_desc": "Active: Invincible for 0.5s, bounce enemy bullets (5s cooldown)",
    "powerup_blood_orb_desc1": "4 blood orbs ({0} dmg/hit, 1.75% lifesteal)",
    "powerup_blood_orb_desc2": "8 blood orbs ({0} dmg/hit, 2.25% lifesteal)",
    "powerup_blood_orb_desc3": "12 blood orbs ({0} dmg/hit, 3% lifesteal)",
    "powerup_blood_aura_desc1": "Blood pulse {0} in 210 radius, heal 2.5% dealt",
    "powerup_blood_aura_desc2": "Blood pulse {0} in 273 radius, heal 5% dealt",
    "powerup_blood_aura_desc3": "Blood pulse {0} in 336 radius, heal 7.5% dealt",
    "powerup_blood_mastery_desc": "Blood effects: +100% dmg, +100% lifesteal",
    "powerup_radial_burst_desc1": "Fire 8 bullets in a circle every 3.5s (uses player damage)",
    "powerup_radial_burst_desc2": "Fire 10 bullets in a circle every 3.0s (uses player damage)",
    "powerup_radial_burst_desc3": "Fire 14 bullets in a circle every 2.0s (uses player damage)",
    "powerup_wall_turrets_desc1": "Walls shoot at enemies (100 + {0} (30%) dmg, 1.5s cooldown, 350px range)",
    "powerup_wall_turrets_desc2": "Walls shoot faster (100 + {0} (30%) dmg, 1.0s cooldown, 425px range)",
    "powerup_wall_turrets_desc3": "Walls fire twin shots (100 + {0} (30%) dmg x2, 1.0s cooldown, 500px range)",
    "powerup_pulse_armor_desc1": "Taking damage pushes nearby enemies back",
    "powerup_pulse_armor_desc2": "Shockwave pushes further and deals 200 + 1% maxHP damage",
    "powerup_pulse_armor_desc3": "Shockwave pushes even further and deals 400 + 1% maxHP damage",
    "powerup_heavy_rounds_desc1": "Bullets 15% larger with slight knockback",
    "powerup_heavy_rounds_desc2": "Bullets 25% larger with increased knockback",
    "powerup_heavy_rounds_desc3": "Bullets 35% larger with strong knockback",
    "powerup_fortified_desc1": "Reduce damage taken by 10% and gain 250 max HP",
    "powerup_fortified_desc2": "Reduce damage taken by 20% and gain 500 (+250) max HP",
    "powerup_fortified_desc3": "Reduce damage taken by 30% and gain 750 (+250) max HP",
    "powerup_special_rounds_desc1": "Every 4th bullet deals +75% bonus damage",
    "powerup_special_rounds_desc2": "Every 3th bullet deals +75% bonus damage",
    "powerup_special_rounds_desc3": "Every 2rd bullet deals +75% bonus damage",
    "powerup_giant_slayer_desc1": "Deal 2.5% of enemy current HP as bonus damage (0.5% vs bosses)",
    "powerup_giant_slayer_desc2": "Deal 4% of enemy current HP as bonus damage (0.8% vs bosses)",
    "powerup_giant_slayer_desc3": "Deal 6% of enemy current HP as bonus damage (1.2% vs bosses)",
    "powerup_curse_desc1": "Curse 25% of enemies, deal +30% damage to cursed foes (greatly reduced vs bosses)",
    "powerup_curse_desc2": "Curse 35% of enemies, deal +45% damage to cursed foes (greatly reduced vs bosses)",
    "powerup_curse_desc3": "Curse 50% of enemies, deal +60% damage to cursed foes (greatly reduced vs bosses)",
    "powerup_celestial_veil_desc": "Nullifies 2 hits per wave, resets at the start of each wave",
    "powerup_volatile": "Volatile",
    "powerup_volatile_desc": "Enemies with 2+ elemental effects take +50% bullet dmg, on death they pulse their active elements to nearby foes",
    "powerup_resonance": "Resonance",
    "powerup_resonance_desc1": "Bullets hitting enemies with active DoTs deal bonus damage equal to 20% of their combined elemental DPS",
    "powerup_resonance_desc2": "Bullets hitting enemies with active DoTs deal bonus damage equal to 30% of their combined elemental DPS",
    "powerup_resonance_desc3": "Bullets hitting enemies with active DoTs deal bonus damage equal to 40% of their combined elemental DPS",
    "powerup_blood_pact": "Blood Pact",
    "powerup_blood_pact_desc": "Sacrifice 20% of your current HP to unleash a blood nova, hitting EVERY enemy for 25% of its max HP + 2.5 damage per HP sacrificed. Bosses resist 60% of it. 3s cooldown",
    "powerup_conduit": "Conduit",
    "powerup_conduit_desc": "Detonate all active DoTs on enemies for 3x their remaining tick damage, then clear the effects. 15s cooldown",
    "powerup_aftershock": "Aftershock",
    "powerup_aftershock_desc": "Emit a shockwave along your last 2s of movement, damaging and knocking back enemies hit. 14s cooldown",
    "powerup_nova": "Nova",
    "powerup_nova_desc": "Freeze all bullets in place for 2 seconds, then release them together at 1.5x speed. 16s cooldown",
    "powerup_heal_power": "Vital Surge",
    "powerup_heal_power_desc1": "All healing received is amplified by 15%. Affects regeneration, lifesteal, and consumables.",
    "powerup_heal_power_desc2": "All healing received is amplified by 20%. Affects regeneration, lifesteal, and consumables.",
    "powerup_heal_power_desc3": "All healing received is amplified by 25%. Affects regeneration, lifesteal, and consumables.",
    "powerup_bountiful": "Cornucopia",
    "powerup_bountiful_desc": "Double consumable drops. Consumables are 50% stronger and last 50% longer. Every 15th kill triggers a jackpot.",

    # Player Feedback
    "player_dodge": "DODGE!",
    "player_parry": "PARRY!",
    "player_phase": "PHASE SHIFT!",
    "player_veil": "VEIL!",
    "player_blood_pact": "BLOOD PACT!",
    "player_conduit": "CONDUIT!",
    "player_aftershock": "AFTERSHOCK!",
    "player_nova": "NOVA!",
    "player_nova_cooldown": "BULLETS RELEASED!",
    "player_ability_on_cooldown": "NOT READY",

    # System Messages
    "system_defensive_processes": "All defensive processes have been terminated.",
    "system_press_any_key": "Press almost any key to continue...",
    "bios_fast_boot": "Press any key to fast boot",
    "system_no_statistics": "No statistics available",
    "system_press_esc_to_return": "Press ESC to return",

    # Loading Screen
    "loading_title": "TopHat-ShooterOS",
    "loading_subtitle": "v6.1 Edition",
    "loading_initializing": "Initializing...",
    "loading_generating_sound": "Generating sound",
    "loading_generating_music": "Generating music",
    "loading_complete": "Asset generation complete!",
    "loading_hint": "Generating procedural audio assets",
    "loading_cached": "All assets loaded from cache",

    # Cheat Menu Buttons
    "cheat_close_instruction": "Press ESC or click X to close",
    "cheat_showing_items": "Showing",
    "cheat_scroll_up": "UP to scroll up",
    "cheat_scroll_down": "DOWN to scroll down",
    "cheat_no_power_ups_selected": "No power-ups selected",

    # OS Task Manager / System Monitoring
    "os_running_processes": "RUNNING PROCESSES",
    "os_no_active_processes": "No active processes",
    "os_process_name": "Process Name",
    "os_version": "Version",
    "os_status": "Status",
    "os_system_performance": "SYSTEM PERFORMANCE",
    "os_system_manager": "System Manager",

    # OS Desktop / System Info
    "os_system_monitor": "System Monitor",
    "os_cpu_idle": "CPU: Idle",
    "os_memory": "Memory",  # label only; live "<used> / <total> GB" appended in code
    "os_network": "Network: Connected",
    "os_tophat_os": "TopHat-ShooterOS",
    "os_edition": "[v6.1 Edition]",
    "os_tophat_button": "TopHat",
    "os_net_indicator": "NET",

    # Stats Labels
    "stats_system_analytics": "System Analytics",
    "stats_run_report": "Run Report",
    "stats_wave_label": "Wave",
    "stats_time_label": "TIME",
    "stats_kills_label": "KILLS",
    "stats_avg_dps": "AVG DPS",
    "stats_play_style_balanced": "Balanced",
    "stats_no_power_ups_selected": "No power-ups selected",
    "stats_bar_wave_max": "[WAVE] Max Reached",
    "stats_bar_kill_best": "[KILL] Best Performance",
    "stats_bar_boss_eliminated": "[BOSS] Eliminated",
    "stats_bar_time_survival": "[TIME] Longest Survival",
    "stats_host_default": "Host",

    # Enemy Labels
    "enemy_active_threats": "ACTIVE THREATS:",

    # General
    "general_yes": "Yes",
    "general_no": "No",
    "general_back": "Back",
    "general_confirm": "Confirm",
    "general_cancel": "Cancel",

    # Wave Celebration
    "wave_cleared_text": "WAVE",
    "boss_defeated_text": "BOSS",
    "wave_celeb_kills": "Kills",
    "wave_celeb_accuracy": "Accuracy",
    "wave_celeb_time": "Time",
    "wave_celeb_coins": "Coins Earned",
    "wave_celeb_max_combo": "Max Combo",

    # Real-time stats overlay
    "real_stats_power": "Power",
    "real_stats_dps": "DPS",
    "real_stats_kills": "Kills",
    "real_stats_cpm": "C/min",

    # Combo display
    "combo_insane": "INSANE!",
    "combo_crazy": "CRAZY!",
    "combo_sick": "SICK!",
    "combo_label": "COMBO!",
    "combo_perfect_wave": "PERFECT WAVE!",
    "combo_perfect_streak": "PERFECT x",
    "combo_coins": "coins!",

    # Micro-reward popups & wave-stats
    "massacre_bonus": "MASSACRE BONUS!",
    "wave_stats_flawless": "FLAWLESS!",
    "wave_stats_title": "WAVE",
    "wave_stats_kills_label": "Kills:",
    "wave_stats_time_label": "Time:",

    # 3D Boss Game HUD
    "game3d_hp": "HP",
    "game3d_ammo": "Ammo",
    "game3d_boss_hp": "Boss HP",
    "game3d_phase": "PHASE",
    "game3d_satellites": "Satellites",
    "game3d_destroy_all": "DESTROY ALL!",
    "game3d_phase_transition": "PHASE TRANSITION!",
    "game3d_paused": "PAUSED",
    "game3d_press_esc_resume": "Press ESC to resume",

    # OS UI
    "os_root_prompt": "root@tophat-shooteros:~$",
    "os_loading": "Loading...",
    "os_shop_navigate": "UP/DOWN/W/S ",
    "os_shop_select": "ENTER/CLICK ",
    "os_shop_exit": "ESC ",
    "shop_available_balance": "Available Balance",
    "os_system_paused": "System paused",
    "os_press_space_continue": "press SPACE to continue",

    # Stats Window
    "stats_window_title": "System Monitor - Player Analytics",
    "stats_tab_lifetime": "Lifetime",
    "stats_tab_last_run": "Last Run",
    "stats_tab_power_ups": "Power-Ups",
    "stats_performance_monitor": "=== SYSTEM PERFORMANCE MONITOR ===",
    "stats_total_sessions": "TOTAL SESSIONS",
    "stats_playtime": "PLAYTIME",
    "stats_peak_kills": "PEAK KILLS",
    "stats_wave_mode_metrics": "WAVE MODE METRICS",
    "stats_time_survival_metrics": "TIME SURVIVAL METRICS",
    "stats_combat": "COMBAT",
    "stats_accuracy": "Accuracy",
    "stats_shots_fired": "Shots Fired",
    "stats_shots_hit": "Shots Hit",
    "stats_damage_dealt": "Damage Dealt",
    "stats_damage_taken": "Damage Taken",
    "stats_elite_kills": "Elite Kills",
    "stats_boss_kills": "Boss Kills",
    "stats_critical_hits": "Critical Hits",
    "stats_movement_survival": "MOVEMENT & SURVIVAL",
    "stats_distance": "Distance",
    "stats_phase_shifts": "Phase Shifts",
    "stats_time_warps": "Time Warps",
    "stats_near_deaths": "Near Deaths",
    "stats_best_streak": "Best Streak",
    "stats_no_hit_streak": "No-Hit Streak",
    "stats_time_at_low_hp": "Time at Low HP",
    "stats_successful_parries": "Successful Parries",
    "stats_time_invincible": "Time Invincible",
    "stats_performance": "PERFORMANCE",
    "stats_peak_dps": "Peak DPS",
    "stats_average_dps": "Average DPS",
    "stats_kills_per_min": "Kills/Min",
    "stats_avg_wave": "Avg Wave",
    "stats_fastest_wave": "Fastest Wave",
    "stats_resources": "RESOURCES",
    "stats_coins_earned": "Coins Earned",
    "stats_coins_spent": "Coins Spent",
    "stats_coins_saved": "Coins Saved",
    "stats_walls_placed": "Walls Placed",
    "stats_consumables": "Consumables",
    "stats_shop_purchases": "Shop Purchases",
    "stats_play_style": "PLAY STYLE",
    "stats_aggression": "Aggression",
    "stats_caution": "Caution",
    "stats_dps_over_time": "DPS OVER TIME",
    "stats_no_graph_data": "No graph data",
    "stats_max_combo": "Max Combo",
    "stats_avg_combo": "Avg Combo",
    "stats_perfect_waves": "Perfect Waves",
    "stats_wave_mode": "WAVE MODE",
    "stats_time_survival_mode": "TIME SURVIVAL",
    "stats_sandbox_mode": "SANDBOX",
    "stats_pvp_mode": "PVP MODE",
    "stats_combat_label": "COMBAT",
    "stats_accuracy_label": "Accuracy",
    "stats_shots_fired_label": "Shots Fired",
    "stats_shots_hit_label": "Shots Hit",
    "stats_no_previous_run": "No previous run statistics available",
    "stats_complete_game_stats": "Complete a game to see detailed run statistics",
    "stats_power_up_breakdown": "POWER-UP BREAKDOWN",
    "stats_timeline": "TIMELINE",
    "stats_effectiveness_ranking": "EFFECTIVENESS RANKING",
    "stats_rank": "RANK",
    "stats_power_up": "POWER-UP",
    "stats_damage": "DAMAGE",
    "stats_no_damage_data": "No damage data available",
    "stats_no_power_up_data": "No power-up data available",

    # Game Over Screen
    "game_over_title": "ALL THREATS NEUTRALIZED",
    "game_over_secure": "SYSTEM STATUS: [*] SECURE",
    "game_over_performance_report": "=== PERFORMANCE REPORT ===",
    "game_over_waves_survived": "Waves Survived:",
    "game_over_threats_eliminated": "Threats Eliminated:",
    "game_over_resources_collected": "Resources Collected:",
    "game_over_mission_duration": "Mission Duration:",
    "game_over_continue": "CONTINUE (WAVE",
    "game_over_save_log": "[S] SAVE LOG",
    "game_over_critical_failure": "CRITICAL SYSTEM FAILURE",
    "game_over_error_msg": "Your system has encountered a critical error and needs to reboot.",
    "game_over_session_diagnostics": "=== SESSION DIAGNOSTICS ===",
    "game_over_wave_reached": "Wave Reached:",
    "game_over_system_uptime": "System Uptime:",
    "game_over_restart_system": "RESTART SYSTEM",
    "game_over_view_logs": "VIEW LOGS",
    "game_over_exit": "EXIT",
    "game_over_error_code": "ERROR CODE: INTEGRITY_DEPLETED_0x00000000",
    "game_over_security_level_max": "SECURITY LEVEL: MAXIMUM | ALL PROCESSES STABLE",
    "game_over_system_failed_footer": "[!] System will remain in failed state until manual restart",
    "game_over_system_secure_footer": "[OK] All systems operational | Defensive grid at maximum efficiency",

    # Victory Screen (wave 60 final boss cleared)
    "victory_title": "MISSION COMPLETE",
    "victory_subtitle": "You purged the final intrusion and cleared all 60 waves!",
    "victory_status": "SYSTEM FULLY SECURED -- THREAT LEVEL ZERO",
    "victory_report_header": "=== FINAL DIAGNOSTICS ===",
    "victory_bosses_defeated": "Bosses Defeated:",
    "victory_continue_endless": "CONTINUE ENDLESS",
    "victory_view_stats": "VIEW STATS",
    "victory_return_menu": "RETURN TO MENU",
    "victory_footer": "[OK] Endless protocol unlocked | How long can you hold the line?",

    # Game Over "cause of death" lines
    "game_over_cause_label": "CAUSE OF TERMINATION",
    "death_contact": "Crushed by",
    "death_boss_contact": "Annihilated by",
    "death_projectile": "Shot down by",
    "death_laser": "Disintegrated by",
    "death_explosion": "Caught in a blast from",
    "death_meteorite": "Bombarded by",
    "death_poison": "Corroded by",
    "death_hazard": "Lost to an arena hazard",
    "death_unknown": "Connection to host terminated",
    "death_boss_tag": "BOSS",

    # HUD/Notifications
    "hud_system_status": "SYSTEM STATUS",
    "hud_integrity": "INTEGRITY:",
    "hud_charges": "CHARGES",
    "hud_processes": "PROCESSES",
    "hud_cache": "CACHE",
    "hud_performance": "Performance",
    "hud_wave": "WAVE:",
    "hud_uptime": "UPTIME:",
    "hud_threats": "THREATS:",
    "notif_wave_initiated": "Wave initiated",
    "notif_wave_cleared": "Wave cleared",

    # Debug Panel
    "debug_panel_diagnostics": "DIAGNOSTICS",
    "debug_panel_fps": "FPS",
    "debug_panel_entities": "Ent",
    "debug_panel_active_effects": "Active Effects",
    "debug_panel_combat_stats": "Combat Stats",
    "debug_panel_damage": "Damage",
    "debug_panel_fire_rate": "Fire Rate",
    "debug_panel_speed": "Speed",
    "debug_panel_low_hp_bonuses": "Low HP Bonuses",
    "debug_panel_rage": "Rage",
    "debug_panel_berserker": "Berserk",
    "debug_panel_effect_speed": "Speed",
    "debug_panel_effect_invuln": "Invuln",
    "debug_panel_effect_fire": "Fire",
    "debug_panel_effect_magnet": "Magnet",
    "debug_panel_effect_time_warp": "Time Warp",
    "debug_panel_effect_phase": "Phase",
    "debug_panel_effect_parry": "Parry",
    "debug_panel_active": "ACTIVE",
    "debug_panel_run_stats": "Run Stats:",
    "debug_panel_wave_label": "Wave",
    "debug_panel_time_label": "Time",

    # Shop tabs
    "shop_tab_player": "PLAYER",
    "shop_tab_bullet": "BULLET",
    "shop_tab_bshapes": "B.SHAPE",
    "shop_tab_shapes": "SHAPES",
    "shop_tab_particles": "FX",
    "shop_tab_desktop": "DESKTOP",
    "shop_tab_cubeskins": "CUBES",
    "shop_scroll_hint": "Scroll with mouse wheel to see all skins",
    "shop_click_equip": "Click to equip",
    "shop_window_title": "Customization Shop",
    "shop_equipped": "[EQUIPPED]",
    "shop_currently_equipped": "Currently Equipped:",
    "shop_customize_appearance": "CUSTOMIZE YOUR APPEARANCE",
    "shop_customize_bullets": "CUSTOMIZE YOUR BULLETS",
    "shop_choose_shape": "CHOOSE YOUR SHAPE",
    "shop_customize_effects": "CUSTOMIZE SHOOTING EFFECTS",
    "shop_customize_desktop": "CUSTOMIZE DESKTOP BACKGROUND",
    "shop_customize_cubeskins": "CUSTOMIZE CUBE ENEMY SKINS",

    # Secret items (shop SECRET tab)
    "shop_tab_secret": "SECRET",
    "shop_customize_secret": "SECRET ITEMS",
    "secret_tophat_name": "Kernel Tophat",
    "secret_tophat_desc": "The kernel's own tophat, entrusted to the one who secured the system.",
    "secret_tophat_unequipped": "[UNEQUIPPED]",
    "secret_click_to_wear": "Click to wear",
    "secret_locked_hint": "Defeat the wave 60 final boss to unlock",
    "secret_unknown_locked_hint": "Unlock condition unknown",
    "secret_orbital_cube_name": "Orbital Cube",
    "secret_orbital_cube_desc": "Knocked out of orbit, the desktop cube found a new one -- around you.",
    "secret_cube_locked_hint": "Earn the 'Escape Velocity' advancement to unlock",
    "secret_cheater_hat_name": "Cheater Hat",
    "secret_cheater_hat_desc": "A very white, very pointy hat for players who know exactly what cd+ does.",
    "victory_secret_unlocked": "[NEW] SECRET UNLOCKED: KERNEL TOPHAT -- equipped! Toggle it in the Shop's SECRET tab.",

    # Desktop Background Skins
    "dbg_default": "OS Grid",
    "dbg_default_desc": "Classic animated circuit board",
    "dbg_neon": "Neon City",
    "dbg_neon_desc": "Pink and purple neon lights",
    "dbg_matrix": "Data Rain",
    "dbg_matrix_desc": "Cascading green code streams",
    "dbg_void": "Deep Void",
    "dbg_void_desc": "Dark space with distant stars",
    "dbg_sunrise": "System Sunrise",
    "dbg_sunrise_desc": "Warm orange horizon glow",
    "dbg_ocean": "Neural Network",
    "dbg_ocean_desc": "Cool blue interconnected nodes",
    "dbg_inferno": "Inferno Core",
    "dbg_inferno_desc": "Red volcanic heat waves",
    "dbg_portal": "Aperture Test",
    "dbg_portal_desc": "Twin portals trade light across the chamber",
    "dbg_horror": "Kernel Panic",
    "dbg_horror_desc": "Dread in the dark - even the cube trembles in fear",
    "dbg_cyber": "Cyberspace",
    "dbg_cyber_desc": "Live circuit traces, data pulses and glitching HUD panels",
    "dbg_casino": "High Roller",
    "dbg_casino_desc": "Green felt, lucky suits, poker chips and gold",
    "dbg_dragon": "Dragon's Lair",
    "dbg_dragon_desc": "Black dragons coil at the edges of a rune-etched dark",

    # Cube Skins
    "csk_default": "System Unit",
    "csk_default_desc": "Classic combat cube",
    "csk_neon": "Neon Pulse",
    "csk_neon_desc": "Bright neon purple energy",
    "csk_ice": "Cryo Core",
    "csk_ice_desc": "Icy blue crystalline shell",
    "csk_gold": "Gold Standard",
    "csk_gold_desc": "Luxurious golden plating",
    "csk_shadow": "Shadow Node",
    "csk_shadow_desc": "Stealth dark mode chassis",
    "csk_plasma": "Plasma Rig",
    "csk_plasma_desc": "Electric blue-purple plasma",
    "csk_matrix": "Data Node",
    "csk_matrix_desc": "Matrix green data streams",
    "csk_companion": "Companion Cube",
    "csk_companion_desc": "It will never threaten to stab you. The heart is purely decorative.",
    "csk_jack": "Jack-O'-Node",
    "csk_jack_desc": "A carved pumpkin lit from within. Too smug to be scared of the dark.",
    "csk_cyber": "Cyberdeck",
    "csk_cyber_desc": "Holographic HUD panels glow on every face.",
    "csk_dice": "Lucky Die",
    "csk_dice_desc": "Roll for initiative. Pips on every face.",
    "csk_d20": "Dragon's Fang",
    "csk_d20_desc": "A true 20-sided die, obsidian and gold. Roll for the lair.",

    # Player Skins
    "skin_default": "System Default",
    "skin_default_desc": "Classic cyan OS interface",
    "skin_neon_pink": "Neon Pink",
    "skin_neon_pink_desc": "Hot magenta cyberpunk style",
    "skin_emerald": "Emerald Tech",
    "skin_emerald_desc": "Advanced green technology",
    "skin_sunset": "Sunset Blaze",
    "skin_sunset_desc": "Fiery orange and red",
    "skin_amethyst": "Amethyst",
    "skin_amethyst_desc": "Royal purple energy",
    "skin_gold": "Golden Aura",
    "skin_gold_desc": "Luxurious golden shine",
    "skin_ice": "Ice Crystal",
    "skin_ice_desc": "Frozen crystalline beauty",
    "skin_shadow": "Shadow Ops",
    "skin_shadow_desc": "Stealth dark mode",
    "skin_rainbow": "Rainbow Wave",
    "skin_rainbow_desc": "Animated rainbow spectrum",
    "skin_matrix": "Matrix Code",
    "skin_matrix_desc": "Green cascading data",
    "skin_void": "Void Walker",
    "skin_void_desc": "Dark purple void energy",
    "skin_plasma": "Plasma Core",
    "skin_plasma_desc": "Electric blue-purple plasma",
    "skin_stars": "Starfall",
    "skin_stars_desc": "Twinkling white-gold sparkle",
    "skin_lightning": "Storm Surge",
    "skin_lightning_desc": "Crackling electric blue",

    # Bullet Skins
    "bullet_default": "System Default",
    "bullet_default_desc": "Classic cyan projectile",
    "bullet_neon_pink": "Neon Pink",
    "bullet_neon_pink_desc": "Hot magenta projectiles",
    "bullet_emerald": "Emerald Tech",
    "bullet_emerald_desc": "Advanced green energy",
    "bullet_sunset": "Sunset Blaze",
    "bullet_sunset_desc": "Fiery orange projectiles",
    "bullet_amethyst": "Amethyst",
    "bullet_amethyst_desc": "Royal purple energy",
    "bullet_gold": "Golden Aura",
    "bullet_gold_desc": "Luxurious golden shots",
    "bullet_ice": "Ice Crystal",
    "bullet_ice_desc": "Frozen crystalline shots",
    "bullet_shadow": "Shadow Ops",
    "bullet_shadow_desc": "Stealth dark projectiles",
    "bullet_rainbow": "Rainbow Wave",
    "bullet_rainbow_desc": "Animated rainbow spectrum",
    "bullet_matrix": "Matrix Code",
    "bullet_matrix_desc": "Green cascading data",
    "bullet_void": "Void Walker",
    "bullet_void_desc": "Dark purple void energy",
    "bullet_plasma": "Plasma Core",
    "bullet_plasma_desc": "Electric blue-purple plasma",
    "bullet_stars": "Starfall",
    "bullet_stars_desc": "Twinkling white-gold shots",
    "bullet_lightning": "Storm Surge",
    "bullet_lightning_desc": "Crackling electric bolts",

    # Shapes
    "shape_hexagon": "Hexagon",
    "shape_hexagon_desc": "Classic hexagonal shape",
    "shape_triangle": "Triangle",
    "shape_triangle_desc": "Sharp triangular form",
    "shape_square": "Square",
    "shape_square_desc": "Solid square shape",
    "shape_circle": "Circle",
    "shape_circle_desc": "Pure circular form",

    # Bullet Shapes
    "bshape_circle": "Classic",
    "bshape_circle_desc": "Standard circle bullet",
    "bshape_triangle": "Shard",
    "bshape_triangle_desc": "Pointed triangular shot",
    "bshape_diamond": "Crystal",
    "bshape_diamond_desc": "Sharp diamond projectile",
    "bshape_square": "Block",
    "bshape_square_desc": "Solid square bullet",
    "bshape_star": "Star",
    "bshape_star_desc": "Six-pointed star burst",
    "bshape_pentagon": "Pentagon",
    "bshape_pentagon_desc": "Five-sided projectile",
    "shop_customize_bshapes": "CUSTOMIZE BULLET SHAPE",
    "particle_default": "System Default",
    "particle_default_desc": "Standard cyan energy",
    "particle_fire": "Flame Burst",
    "particle_fire_desc": "Burning fire particles",
    "particle_ice": "Frost Shards",
    "particle_ice_desc": "Icy crystalline fragments",
    "particle_toxic": "Toxic Cloud",
    "particle_toxic_desc": "Poisonous green gas",
    "particle_plasma": "Plasma Burst",
    "particle_plasma_desc": "Electric purple energy",
    "particle_gold": "Golden Sparkle",
    "particle_gold_desc": "Shimmering gold dust",
    "particle_shadow": "Dark Smoke",
    "particle_shadow_desc": "Mysterious shadow trails",
    "particle_rainbow": "Rainbow Burst",
    "particle_rainbow_desc": "Colorful confetti spray",
    "particle_stars": "Star Trail",
    "particle_stars_desc": "Twinkling star particles",
    "particle_hearts": "Love Burst",
    "particle_hearts_desc": "Cute heart particles",
    "particle_lightning": "Lightning Spark",
    "particle_lightning_desc": "Electric yellow bolts",
    "particle_void": "Void Energy",
    "particle_void_desc": "Dark dimensional rifts",
    "particle_amethyst": "Crystal Bloom",
    "particle_amethyst_desc": "Violet crystal shimmer",
    "particle_matrix": "Code Rain",
    "particle_matrix_desc": "Cascading green data",

    # Cosmetic Packs (discounted theme trios)
    "shop_tab_packs": "PACKS",
    "shop_customize_packs": "Theme Bundles -- 40% Off",
    "pack_owned": "OWNED",
    "pack_buy": "BUY BUNDLE",
    "pack_includes": "Player + Bullet + Particle",
    "pack_gold": "Gold Bundle",
    "pack_gold_desc": "Every Golden Aura cosmetic",
    "pack_ice": "Ice Bundle",
    "pack_ice_desc": "Every Ice Crystal cosmetic",
    "pack_shadow": "Shadow Bundle",
    "pack_shadow_desc": "Every Shadow Ops cosmetic",
    "pack_rainbow": "Rainbow Bundle",
    "pack_rainbow_desc": "Every Rainbow Wave cosmetic",
    "pack_void": "Void Bundle",
    "pack_void_desc": "Every Void Walker cosmetic",
    "pack_plasma": "Plasma Bundle",
    "pack_plasma_desc": "Every Plasma Core cosmetic",
    "pack_sunset": "Sunset Bundle",
    "pack_sunset_desc": "Sunset skins with a flame trail",
    "pack_emerald": "Emerald Bundle",
    "pack_emerald_desc": "Emerald skins with a toxic trail",
    "pack_neon_pink": "Neon Pink Bundle",
    "pack_neon_pink_desc": "Neon Pink skins with heart bursts",
    "pack_amethyst": "Amethyst Bundle",
    "pack_amethyst_desc": "Every Amethyst cosmetic",
    "pack_matrix": "Matrix Bundle",
    "pack_matrix_desc": "Every Matrix Code cosmetic",
    "pack_stars": "Starfall Bundle",
    "pack_stars_desc": "Every Starfall cosmetic",
    "pack_lightning": "Storm Bundle",
    "pack_lightning_desc": "Every Storm Surge cosmetic",

    # Legendary Panel
    "legendary_panel_title": "LEGENDARY",
    "legendary_chronos": "Chronos",
    "legendary_phase": "Phase",
    "legendary_parry": "Parry",
    "legendary_active": "ACTIVE",
    "legendary_ready": "Ready",
    "legendary_dashing": "DASHING",
    "legendary_volatile": "Volatile",
    "legendary_resonance": "Resonance",
    "legendary_blood_pact": "Blood Pact",
    "legendary_conduit": "Conduit",
    "legendary_nova": "Nova",
    "legendary_passive": "PASSIVE",
    "legendary_frozen": "FROZEN",

    "notif_boss_detected": "BOSS PROCESS DETECTED",
    "notif_boss_terminated": "Boss process terminated",
    "notif_installed": "Installed:",
    "notif_integrity_compromised": "Integrity compromised: -",
    "notif_integrity_restored": "System integrity restored: +",
    "notif_resource_acquired": "Resource acquired: +",
    "notif_execute": "> EXECUTE:",
    "notif_cooldown": "cooldown:",
    "notif_process_terminated": "Process terminated:",
    "notif_processes_terminated": "Processes terminated:",

    # Help System
    "help_window_title": "Help System - Terminal",
    "help_available_commands": "  AVAILABLE COMMANDS",
    "help_controls_keybindings": "CONTROLS & KEYBINDINGS",
    "help_gameplay_topic": "GAME MODES",
    "help_power_ups_topic": "POWER-UPS REFERENCE",
    "help_powerup_locked_name": "??? - Undiscovered",
    "help_powerup_locked_desc": "[LOCKED] Discover this power-up during a run to reveal its details.",
    "help_enemies_topic": "ENEMY TYPES",
    "help_bosses_topic": "BOSS INFORMATION",
    "help_shop_topic": "SHOP ITEMS",
    "help_clear_command": "Clear the screen",
    "help_command_separator": "--------------------------------------",
    "help_launch_topics": "play/survival/sandbox/stats/settings/quit",
    "help_launching_icon": "Launching $1...",
    "help_opening_icon": "Opening $1...",
    "help_executing_icon": "Executing $1...",
    "help_unknown_command": "Unknown command:",
    "help_type_help": "Type 'help' for available commands",
    "help_error_executing": "Error executing command:",

    # Help System - Command descriptions
    "help_cmd_help": "Show this command list",
    "help_cmd_controls": "View controls and keybindings",
    "help_cmd_gameplay": "Game modes and mechanics",
    "help_cmd_powerups": "Complete power-up reference",
    "help_cmd_enemies": "Enemy types and behaviors",
    "help_cmd_bosses": "Boss information",
    "help_cmd_shop": "Shop items and costs",
    "help_cmd_launch_icons": "Launch desktop icons by name",

    # Help System - Controls section
    "help_movement": "MOVEMENT",
    "help_combat": "COMBAT",
    "help_abilities": "ABILITIES",
    "help_menu": "MENU",
    "help_movement_desc": "Move player",
    "help_wasd": "W/A/S/D ............ Move player",
    "help_arrow_keys": "Arrow Keys ......... Alternative movement",
    "help_left_mouse": "Left Mouse ......... Shoot",
    "help_space": "Space .............. Shoot (alternative)",
    "help_q": "Q .................. Activate Legendary Powers",
    "help_e": "E .................. Place Wall",
    "help_esc": "ESC ................ Pause / Return to menu",
    "help_f11": "F11 ................ Toggle Fullscreen",

    # Help System - Gameplay section
    "help_wave_mode": "WAVE-BASED MODE",
    "help_wave_mode_desc": "- Clear waves of enemies\n  - Boss appears every 5th wave\n  - Choose power-up after each wave\n  - Shop opens after power-up selection",
    "help_survival_mode": "SURVIVAL MODE",
    "help_survival_mode_desc": "- Survive endless enemy hordes\n  - Enemies spawn continuously\n  - Boss appears every 60 seconds",
    "help_sandbox_mode": "SANDBOX MODE",
    "help_sandbox_mode_desc": "- Testing mode with spawner controls\n  - Experiment with different scenarios",

    # Help System - Power-ups section
    "help_common_powerups": "COMMON POWER-UPS",
    "help_elemental_orbs": "ELEMENTAL ORBS",
    "help_elemental_auras": "ELEMENTAL AURAS",
    "help_legendary_powerups": "LEGENDARY POWER-UPS (Press Q)",

    # Help System - Enemy section
    "help_enemy_circle": "CIRCLE (Chaser)",
    "help_enemy_cube": "CUBE (Turret)",
    "help_enemy_triangle": "TRIANGLE (Dasher)",
    "help_enemy_star": "STAR (Tank)",
    "help_enemy_hexagon": "HEXAGON (Warper)",
    "help_enemy_elite": "ELITE VARIANTS",

    # Help System - Boss section
    "help_boss_spawning": "BOSS SPAWNING",
    "help_boss_mechanics": "BOSS MECHANICS",
    "help_boss_attacks": "BOSS ATTACKS",
    "help_boss_rewards": "REWARDS",

    # Help System - Shop section
    "help_available_items": "AVAILABLE ITEMS",
    "help_cost_scaling": "COST SCALING",
    "help_earning_coins": "EARNING COINS",
    "help_shop_access": "SHOP ACCESS",

    # Help System - Powerup names
    "help_double_shot": "Double Shot - Fire 2 bullets per shot",
    "help_rotating_shield": "Rotating Shield - Orbiting protective shield",
    "help_magical_bullets": "Magical Bullets - Bullets track enemies",
    "help_piercing_shots": "Piercing Shots - Bullets pass through enemies",
    "help_multi_shot": "Multi Shot - Shoots in 3 directions",
    "help_explosive_bullets": "Explosive Bullets - Bullets explode on impact",
    "help_life_steal": "Life Steal - Gain HP from kills",
    "help_rapid_fire": "Rapid Fire - Increased fire rate",
    "help_max_health": "Max Health - Increase max HP",
    "help_speed_boost": "Speed Boost - Permanent speed increase",
    "help_bullet_speed": "Bullet Speed - Faster bullets",
    "help_lucky_coins": "Lucky Coins - Doubles coins collected",
    "help_wall_master": "Wall Master - Place stronger walls",
    "help_regeneration": "Regeneration - Slowly restore HP",
    "help_dodge_chance": "Dodge Chance - Chance to evade damage",
    "help_critical_hit": "Critical Hit - Random critical damage",
    "help_blood_bullets": "Blood Bullets - Lifesteal on hit",
    "help_bullet_ricochet": "Bullet Ricochet - Bullets ricochet off enemies",
    "help_slow_field": "Slow Field - Enemies move slower nearby",
    "help_rage": "Rage - Damage increases at low HP",
    "help_berserker": "Berserker - Attack speed at low HP",
    "help_thorns": "Thorns - Reflect damage to attackers",
    "help_bullet_split": "Bullet Split - Bullets split on impact",
    "help_chain_lightning": "Chain Lightning - Damage chains between enemies",
    "help_frost_shots": "Frost Shots - Bullets slow enemies",
    "help_poison_shot": "Poison Shot - Poison bullets with DoT",
    "help_fire_bullets": "Fire Bullets - Fire damage over time",
    "help_wind_bullets": "Wind Bullets - Bullets push enemies",
    "help_overcharge": "Overcharge - Bullets gain power over distance",
    "help_echo_shots": "Echo Shots - Bullets leave damaging trails",
    "help_poison_orb": "Poison Orb - Poison elemental orb",
    "help_fire_orb": "Fire Orb - Fire elemental orb",
    "help_lightning_orb": "Lightning Orb - Lightning elemental orb",
    "help_wind_orb": "Wind Orb - Wind elemental orb",
    "help_frost_orb": "Frost Orb - Frost elemental orb",
    "help_arcane_orb": "Arcane Orb - Arcane elemental orb",
    "help_blood_orb": "Blood Orb - Blood elemental orb",
    "help_fire_aura": "Fire Aura - Fire damage over time aura",
    "help_lightning_aura": "Lightning Aura - Lightning chains between enemies",
    "help_poison_aura": "Poison Aura - Poison damage over time aura",
    "help_wind_aura": "Wind Aura - Periodic gust that blasts enemies away",
    "help_arcane_aura": "Arcane Aura - Enhanced arcane damage aura",
    "help_blood_aura": "Blood Aura - Damage aura with lifesteal",
    "help_time_warp": "Time Warp - Slow down time globally",
    "help_gravity_well": "Gravity Well - Pull enemies toward you",
    "help_phase_shift": "Phase Shift - Teleport dash through enemies",
    "help_parry": "Parry - Invincible + bounce bullets",
    "help_rotating_orbs": "Rotating Orbs - All elemental orbs at once",
    "help_fire_mastery": "Fire Mastery - Enhance all fire effects",
    "help_poison_mastery": "Poison Mastery - Enhance all poison effects",
    "help_frost_mastery": "Frost Mastery - Enhance all frost effects",
    "help_arcane_mastery": "Arcane Mastery - Enhance all arcane effects",
    "help_lightning_mastery": "Lightning Mastery - Enhance lightning effects",
    "help_wind_mastery": "Wind Mastery - Enhance all wind effects",
    "help_blood_mastery": "Blood Mastery - Enhance all blood effects",
    "help_arcane_bullets": "Arcane Bullets - Arcane-enhanced bullet damage",
    "help_radial_burst": "Radial Burst - Periodically fire a ring of bullets",
    "help_wall_turrets": "Wall Sentinels - Walls shoot at nearby enemies",
    "help_pulse_armor": "Pulse Armor - Taking damage emits a shockwave",
    "help_heavy_rounds": "Heavy Rounds - Larger bullets with knockback",
    "help_fortified": "Fortified - Reduce damage taken, gain max HP",
    "help_special_rounds": "Special Rounds - Every 5th bullet deals bonus damage",
    "help_giant_slayer": "Giant Slayer - Bonus damage vs high-HP enemies",
    "help_curse": "Curse - Curses random enemies so you deal bonus damage to them",
    "help_celestial_veil": "Celestial Veil - Nullifies two hits per wave",
    "help_volatile": "Volatile - Enemies with 2+ DoTs take +50% dmg",
    "help_resonance": "Resonance - Bullets on DoT targets deal elemental bonus",
    "help_blood_pact": "Blood Pact - Sacrifice HP to blast every enemy for a share of its max HP",
    "help_conduit": "Conduit - Detonate all DoTs for 3x burst damage",
    "help_aftershock": "Aftershock - Shockwave traces your movement path",
    "help_nova": "Nova - Freeze bullets then release at +50% speed",
    "help_heal_power": "Heal Power - Increase all healing received",
    "help_bountiful": "Cornucopia - More consumable drops, boosted effects",

    # Help System - Shop items
    "help_shop_damage_plus": "Damage + (13 CR base)",
    "help_shop_damage_plus_desc": "Bullet damage boost",
    "help_shop_fire_rate_plus": "Fire Rate + (13 CR base)",
    "help_shop_fire_rate_plus_desc": "Fire rate boost",
    "help_shop_move_speed_plus": "Move Speed + (10 CR base)",
    "help_shop_move_speed_plus_desc": "Movement speed boost",
    "help_shop_max_health_plus": "Max Health + (14 CR base)",
    "help_shop_max_health_plus_desc": "Large maximum HP increase",
    "help_shop_bullet_speed_plus": "Bullet Speed + (9 CR base)",
    "help_shop_bullet_speed_plus_desc": "Bullet velocity boost",
    "help_shop_wall_x4": "Wall x10 (18 CR base)",
    "help_shop_wall_x4_desc": "Buy 10 deployable walls",

    # Help System - Misc
    "help_wave_mode_info": "Wave Mode: Every 5th wave (5, 10, 15...)",
    "help_survival_mode_info": "Survival Mode: Every 60 seconds",
    "help_enemy_chaser": "- Normal chasing enemies\n  - Follows player movement\n  - Most common enemy type",
    "help_enemy_turret": "- Stationary or slow-moving shooters\n  - Fires projectiles at player\n  - Keep your distance",
    "help_enemy_dasher": "- Fast dash attackers\n  - Quick bursts of speed\n  - Dangerous at close range",
    "help_enemy_tank": "- High HP enemies\n  - Requires many hits to defeat\n  - Dashes when getting close",
    "help_enemy_warper": "- Teleporting chaos enemy\n  - Unpredictable movement\n  - Can appear anywhere suddenly",
    "help_enemy_elite_desc": "- Tougher versions of all enemy types\n  - Drop more coins when defeated\n  - Spawn in later waves",
    "help_boss_every_5th": "Wave Mode: Every 5th wave (5, 10, 15...)",
    "help_boss_every_60_sec": "Survival Mode: Every 60 seconds",
    "help_cost_scaling_formula": "- Shop items have strict purchase caps\n  - Each buy is stronger and costs baseCost * 1.8^bought",
    "help_kill_enemies_to_collect": "- Kill enemies to collect coins",
    "help_elite_drop_more": "- Elite enemies drop more coins",
    "help_boss_drop_large": "- Bosses drop large amounts",
    "help_opens_after_powerup": "- Opens after power-up selection",
    "help_available_between_waves": "- Available between waves",

    # Game Notifications and UI
    "game_wave_announcement_main": "*** WAVE ***",
    "game_instructions_wall": "E: Wall | ESC: Pause",
    "game_wall_place": "[Release E] Place Wall",
    "game_wall_place_remaining": "remaining",
    "game_get_ready": "GET READY!",
    "game_boss_wave_prefix": "BOSS WAVE ",
    "game_incoming": "INCOMING",
    "game_press_enter_to_start": "Press ENTER to start",
    "game_no_data": "No data",
    "game_no_graph_data": "No graph data",
    "game_no_previous_run": "No previous run statistics available",
    "game_complete_game_stats": "Complete a game to see detailed run statistics",
    "game_no_power_up_data": "No power-up data available",
    "game_wave_label": "Wave ",
    "game_best_streak": "Best Streak",

    # Stats Window
    "stats_time_column_label": "TIME",
    "stats_damage_column_label": "DAMAGE",
    "stats_dealed_abbrev": "Damage Dealt",
    "stats_taken_abbrev": "Damage Taken",
    "stats_level_prefix": "Lvl ",
    "stats_total": "Total",
    "stats_legendary_count": "Legendary",
    "stats_common_count": "Common",

    # Sandbox Mode
    "sandbox_spawn_enemies": "Spawn Enemies:",
    "sandbox_spawn_10_random": "Spawn 10 Random",
    "sandbox_spawn_bosses": "Spawn Bosses:",
    "sandbox_god_mode": "God Mode:",
    "sandbox_freeze_enemies": "Freeze Enemies:",
    "sandbox_clear_all_enemies": "Clear All Enemies",
    "sandbox_wave": "Wave:",
    "sandbox_difficulty": "Difficulty:",
    "sandbox_hp": "HP:",
    "sandbox_enemies": "Enemies:",
    "sandbox_heal_full": "Heal to Full HP",
    "sandbox_add_coins": "Add 1000 Coins",
    "sandbox_open_shop": "Open Shop",
    "sandbox_roll_power_ups": "Roll Power-Ups",
    "sandbox_title": "SANDBOX MODE",
    "sandbox_tab_enemies": "Enemies",
    "sandbox_tab_bosses": "Bosses",
    "sandbox_tab_controls": "Controls",
    "sandbox_coins": "Coins:",
    "sandbox_wave_minus": "Wave -",
    "sandbox_wave_plus": "Wave +",
    "sandbox_diff_minus": "Diff -",
    "sandbox_diff_plus": "Diff +",
    "sandbox_toggle": ">>",
    "sandbox_close": "X",
    "sandbox_setup_title": "SANDBOX SETUP",
    "sandbox_setup_subtitle": "Configure your loadout, pick a preset, or pull the average build for any wave.",
    "sandbox_stat_max_hp": "Max HP",
    "sandbox_stat_damage": "Damage",
    "sandbox_stat_fire_rate": "Fire Rate",
    "sandbox_stat_move_speed": "Move Speed",
    "sandbox_stat_bullet_speed": "Bullet Speed",
    "sandbox_stat_walls": "Walls",
    "sandbox_stat_coins": "Coins",
    "sandbox_stat_start_wave": "Start Wave",
    "sandbox_presets": "PRESETS",
    "sandbox_preset_fresh": "Fresh Start",
    "sandbox_preset_early": "Early Game (W5)",
    "sandbox_preset_mid": "Mid Game (W15)",
    "sandbox_preset_late": "Late Game (W30)",
    "sandbox_preset_end": "End Game (W60)",
    "sandbox_preset_glass": "Glass Cannon",
    "sandbox_preset_tank": "Juggernaut",
    "sandbox_apply_wave_avg": "Use Wave Average",
    "sandbox_start_run": "Start Sandbox",
    "sandbox_back": "Back",
    "sandbox_custom_loadout": "Custom loadout",

    # Cheat Menu
    "cheat_menu_title": "CHEAT MENU (TESTER BUILD)",
    "cheat_menu_close": "Press ESC or click X to close",
    "cheat_tab_waves": "1. Waves",
    "cheat_tab_power": "2. Power",
    "cheat_tab_stats": "3. Stats",
    "cheat_tab_perma": "4. Perma",
    "cheat_tab_enemies": "5. Enemies",
    "cheat_current_wave": "Current Wave:",
    "cheat_waves_until_boss": "Waves until Boss:",
    "cheat_enemies_alive": "Enemies alive:",
    "cheat_skip_wave": "Skip Current Wave",
    "cheat_advance_wave": "Advance to Next Wave",
    "cheat_trigger_boss": "Trigger Boss Wave",
    "cheat_activate_consumable": "Click to activate consumable (30 seconds)",
    "cheat_speed_boost": "Speed Boost",
    "cheat_invincibility": "Invincibility",
    "cheat_fire_rate": "Fire Rate",
    "cheat_magnet": "Magnet",
    "cheat_player_stats": "Player Stats (Click buttons to modify)",
    "cheat_health": "Health:",
    "cheat_max_health": "Max Health:",
    "cheat_coins": "Coins:",
    "cheat_speed": "Speed:",
    "cheat_health_full": "Full",
    "cheat_health_half": "Half",
    "cheat_health_low": "Low",
    "cheat_health_num": "100",
    "cheat_speed_normal": "Normal",
    "cheat_speed_fast": "Fast",
    "cheat_speed_max": "Max",
    "cheat_modify_stats": "Tip: Modify stats to test different scenarios",
    "cheat_power_ups_available": "Permanent Power-Ups (Click to add/upgrade)",
    "cheat_currently_owned": "Currently Owned:",
    "cheat_none": "None",
    "cheat_all_power_ups": "All Available Power-Ups (scroll with UP/DOWN):",
    "cheat_active_enemies": "Active Enemies",
    "cheat_no_enemies": "No enemies currently alive",
    "cheat_discovery_codex": "Discovery Codex:",
    "cheat_discover_all": "Discover All Power-Ups",
    "cheat_undiscover_all": "Un-Discover All",

    # Power-up Installer
    "power_up_installer_title": "LEGENDARY UPGRADE INSTALLER",
    "power_up_installer_title_generic": "PROCESS UPGRADE MANAGER",
    "power_up_upgrade_tier": "UPGRADE TIER:",
    "power_up_installer_close": "X",
    "power_up_select_upgrade": "v SELECT UPGRADE TO INSTALL:",
    "power_up_rolling": "[!] ROLLING...",
    "power_up_reroll_options": "[R] Reroll Options",
    "power_up_all_installed": "ALL PACKAGES INSTALLED",
    "power_up_all_installed_msg": "Maximum loadout achieved. All available upgrades are already installed.",
    "power_up_continue": "CONTINUE",
    "power_up_new_badge": "NEW",

    # PvP Lobby
    "pvp_title": "PVP MODE",
    "pvp_host_game": "HOST GAME",
    "pvp_join_game": "JOIN GAME",
    "pvp_configure_hosting": "CONFIGURE HOSTING",
    "pvp_nickname": "Nickname:",
    "pvp_max_players": "Max Players:",
    "pvp_show_ips": "Show IPs in lobby",
    "pvp_enable_interpolation": "Enable Interpolation",
    "pvp_teams_mode": "Teams Mode",
    "pvp_enable_teams": "Enable Teams Game Mode",
    "pvp_num_teams": "Number of Teams:",
    "pvp_start_hosting": "START HOSTING",
    "pvp_hosting_game": "HOSTING GAME",
    "pvp_local_ip": "Local IP:",
    "pvp_port": "Port:",
    "pvp_players_count": "Players:",
    "pvp_click_assign_team": "Click player to assign team:",
    "pvp_you_host": " (You - Host)",
    "pvp_connected_players": "Connected Players:",
    "pvp_teams_enabled": "Teams mode enabled",
    "pvp_show_ip": "Show IP",
    "pvp_join_game_title": "JOIN GAME",
    "pvp_host_ip": "Host IP:",
    "pvp_click_cycle_tabs": "Click to edit  |  Tab to cycle",
    "pvp_connect": "CONNECT",
    "pvp_connecting": "CONNECTING...",
    "pvp_please_wait": "Please wait",
    "pvp_timeout_in": "Timeout in",
    "pvp_game_lobby": "GAME LOBBY",
    "pvp_connected_label": "Connected Players:",
    "pvp_click_badge_team": "(click badge to change team)",
    "pvp_you": " (You)",
    "pvp_start_game": "START GAME",
    "pvp_need_2_players": "NEED 2+ PLAYERS",
    "pvp_connected": "CONNECTED!",
    "pvp_waiting_for_host": "Waiting for host to start...",
    "pvp_players_in_lobby": "Players in lobby:",
    "pvp_connection_error": "CONNECTION ERROR",
    "pvp_back": "BACK",
    "pvp_player_num": "Player ",
    "pvp_failed_start_host": "Failed to start host: ",
    "pvp_failed_connect": "Failed to connect: ",
    "pvp_connection_timeout": "Connection timeout",
    "pvp_host_disconnected": "Host disconnected",

    # PvP Config - Game Stats section
    "pvp_game_stats": "GAME STATS",
    "pvp_stat_hp": "HP",
    "pvp_stat_kill_limit": "KILL LIMIT",
    "pvp_stat_respawn": "RESPAWN (s)",
    "pvp_stat_speed": "SPEED",
    "pvp_stat_damage": "DAMAGE",
    "pvp_stat_fire_rate": "FIRE RATE (s)",
    "pvp_stat_bullet_speed": "BULLET SPEED",
    "pvp_stat_bullet_radius": "BULLET RADIUS",
    "pvp_stat_start_walls": "START WALLS",
    "pvp_stat_time_limit": "TIME LIMIT",
    "pvp_stat_net_quality": "NET QUALITY",
    "pvp_net_quality_ultra": "Ultra (128 ticks)",
    "pvp_net_quality_high": "High (64 ticks)",
    "pvp_net_quality_medium": "Medium (32 ticks)",
    "pvp_net_quality_low": "Low (20 ticks)",
    "pvp_value_off": "OFF",
    "pvp_local_net_multiplayer": "[ LOCAL NETWORK MULTIPLAYER ]",
    "pvp_share_ip_info": "Share your Local IP with friends on the same network",

    # PvP Teams
    "pvp_team_red": "Red",
    "pvp_team_blue": "Blue",
    "pvp_team_green": "Green",
    "pvp_team_yellow": "Yellow",
    "pvp_team_orange": "Orange",
    "pvp_team_purple": "Purple",
    "pvp_team_none": "None",

    "stats_no_powerups_selected": "No power-ups selected",
    "stats_no_graph_data_short": "No graph data",
    "stats_controls_footer": "[TAB/ESC] Return  [R] Restart  [Q] Menu",

    # Lifetime Stats Labels
    "stats_movement_label": "MOVEMENT",
    "stats_distance_label": "Distance",
    "stats_phase_shifts_label": "Phase Shifts",
    "stats_time_warps_label": "Time Warps",
    "stats_near_deaths_label": "Near Deaths",
    "stats_best_streak_label": "Best Streak",
    "stats_time_low_hp_label": "Time Low HP",
    "stats_performance_label": "PERFORMANCE",
    "stats_peak_dps_label": "Peak DPS",
    "stats_avg_dps_label": "Avg DPS",
    "stats_kills_min_label": "Kills/Min",
    "stats_avg_wave_label": "Avg Wave",
    "stats_fast_wave_label": "Fast Wave",
    "stats_resources_label": "RESOURCES",
    "stats_coins_earned_label": "Coins Earned",
    "stats_coins_spent_label": "Coins Spent",
    "stats_coins_saved_label": "Coins Saved",
    "stats_walls_placed_label": "Walls Placed",
    "stats_consumables_label": "Consumables",
    "stats_shop_purchases_label": "Shop Purchases",
    "stats_play_style_label": "PLAY STYLE",
    "stats_aggression_label": "Aggression",
    "stats_caution_label": "Caution",
    "stats_dps_over_time_label": "DPS OVER TIME",
    "stats_play_style_aggressive": "Aggressive",
    "stats_play_style_defensive": "Defensive",
    "stats_play_style_mobile": "Mobile",
    "stats_play_style_tank": "Tank",

    # Gamemode Names and Descriptions
    "gamemode_wave_based_name": "Wave-Based",
    "gamemode_wave_based_desc": "Fight through waves of enemies. Defeat bosses every 5 waves for legendary upgrades.",
    "gamemode_time_survival_name": "Time Survival",
    "gamemode_time_survival_desc": "Survive as long as possible. Difficulty increases over time.",
    "gamemode_sandbox_name": "Sandbox",
    "gamemode_sandbox_desc": "Test and experiment with enemies, bosses, and game mechanics.",
    "gamemode_pvp_name": "PVP",
    "gamemode_pvp_desc": "Battle against another players in real-time combat. First to 5 kills wins!",
    "gamemode_roguelite_name": "Roguelite",
    "gamemode_roguelite_desc": "Crawl 4 themed dungeon floors, loot keys and relics, defeat floor bosses, and bank shards.",
    "roguelite_setup_title": "DUNGEON SETUP",
    "roguelite_setup_subtitle": "CONFIGURE LOADOUT  //  PICK KIT  ·  SET HEAT  ·  LAUNCH",
    "roguelite_unlocks_title": "SHARD UNLOCKS",
    "roguelite_data_shards": "Data Shards",
    "roguelite_shards": "Shards",
    "roguelite_shards_short": "shards",
    "roguelite_cores": "Cores",
    "roguelite_cores_short": "Cores",
    "roguelite_heat": "Heat",
    "roguelite_floor": "Floor",
    "roguelite_level_up": "LEVEL UP!",
    "roguelite_endless": "Endless",
    "roguelite_pressure": "Pressure",
    "roguelite_elite": "Elite",
    "dungeon_rooms": "Rooms",
    "dungeon_rooms_cleared": "Rooms Cleared",
    "dungeon_keys": "Keys",
    "dungeon_door_locked": "LOCKED - find a key",
    "dungeon_door_unlock": "Use key to unlock",
    "dungeon_shop_prompt": "[E] Open shop",
    "dungeon_portal_prompt": "Enter portal to descend",
    "dungeon_floor_select_title": "CHOOSE FLOOR THEME",
    "dungeon_floor_select_tip": "Each theme brings its own processes, hazards, and floor boss. Used themes won't reappear this run.",
    "roguelite_victory_title": "SYSTEM PURGED",
    "roguelite_victory_subtitle": "Every floor boss is down. The OS is yours, cash out, or push the kernel deeper into the endless loop.",
    "roguelite_loop_cleared_title": "LOOP CLEARED",
    "roguelite_loop_cleared_subtitle": "Another loop secured. Bank your spoils, or descend again for richer rewards and fiercer processes.",
    "roguelite_relics_carried": "Relics carried",
    "roguelite_relics_none": "No relics this run.",
    "roguelite_continue_endless": "Continue (Endless Loop)",
    "roguelite_cash_out": "Cash Out",
    "roguelite_victory_controls": "[SPACE] continue    [ESC] cash out    [←/->] switch    [ENTER] confirm",
    "dungeon_floor_boss": "Floor Boss",
    "dungeon_final_floor_label": "FINAL BOSS",
    "dungeon_final_floor_desc": "The stack ends here. No sectors left to roll, only the last process. Step into the arena and face the Omega Entity.",
    "dungeon_final_floor_warning": "No more sectors. No turning back.",
    "dungeon_theme_firewall": "Firewall",
    "dungeon_theme_firewall_desc": "Heat-hardened defense grid. Steady shooters and blockers hold every room.",
    "dungeon_theme_recycle_bin": "Recycle Bin",
    "dungeon_theme_recycle_bin_desc": "Discarded process swarms. Endless weak chasers backed by tanky stars.",
    "dungeon_theme_registry": "Registry",
    "dungeon_theme_registry_desc": "Ordered killers. Crosses and cubes fire precise, telegraphed volleys.",
    "dungeon_theme_network": "Network",
    "dungeon_theme_network_desc": "Hot packet traffic. Dashers, snipers, and hit-and-run strikes.",
    "dungeon_theme_kernel": "Kernel",
    "dungeon_theme_kernel_desc": "Deep system space. Heavy units and mage processes with real firepower.",
    "dungeon_theme_cache": "Cache",
    "dungeon_theme_cache_desc": "Mirrored memory. Phantoms, tricksters, and teleporting chaos.",
    "dungeon_theme_corrupted_sector": "Corrupted Sector",
    "dungeon_theme_corrupted_sector_desc": "Anything goes. Every process type, more elites, and the biggest payouts.",
    "roguelite_best": "Record",
    "roguelite_kits": "Kits",
    "roguelite_families": "Families",
    "roguelite_relics": "Relics",
    "roguelite_unlocked": "OWNED",
    "roguelite_locked": "LOCKED",
    "roguelite_unlock_hint": "Spend shards in Unlocks",
    "roguelite_unlocks": "[U] Unlock Shop",
    "roguelite_start": "[ENTER] Start Run",
    "roguelite_back": "[ESC] Back",
    "roguelite_setup_controls": "Kit A/D  |  Heat W/S  |  Shop U  |  Start ENTER",
    "roguelite_sector_controls": "Theme A/D  |  Deploy ENTER",
    "roguelite_unlock_controls": "Back ESC/U",
    "roguelite_unlock_shop_controls": "1-4/A-D: Group  |  Arrows: Item  |  ENTER: Buy  |  ESC: Back",
    "roguelite_scroll_hint": "Scroll to see more",
    "roguelite_unlock_shop_hint": "Spend shards and high-Heat cores here. Late unlocks need Heat 2+ economies.",
    "roguelite_unlock_categories": "GROUPS",
    "roguelite_unlock_details": "DETAILS",
    "roguelite_unlock_cat_kits": "Kits",
    "roguelite_unlock_cat_families": "Families",
    "roguelite_unlock_cat_relics": "Relics",
    "roguelite_unlock_cat_challenge": "Challenge",
    "roguelite_cost": "Cost",
    "roguelite_ready_to_buy": "READY",
    "roguelite_not_enough_shards": "NEED RESOURCES",
    "roguelite_buy_unlock": "[ENTER] BUY",
    "roguelite_need_more_shards": "NEED RESOURCES",
    "roguelite_already_unlocked": "OWNED",
    "roguelite_unlock_heat": "Heat",
    "roguelite_unlock_wave_surge": "Wave Surge",
    "roguelite_unlock_desc_wave_surge": "Shifts every floor boss to a harder definition per tier, with bigger boss payouts.",
    "roguelite_wave_surge": "Wave Surge",
    "roguelite_unlock_desc_family": "Adds this power-up family to future draft pools.",
    "roguelite_unlock_desc_family_core": "Adds base stat, bullet, economy, and survival upgrades to drafts.",
    "roguelite_unlock_desc_family_shield": "Adds armor, wall, thorns, and shield tools to drafts.",
    "roguelite_unlock_desc_family_arcane": "Adds Arcane Aura, Arcane Bullets, Echo Shots, Gravity Well, and Overcharge.",
    "roguelite_unlock_desc_family_fire": "Adds burn aura, fire rounds, fire orb, and Fire Mastery drafts.",
    "roguelite_unlock_desc_family_frost": "Adds slow shots, frost orb, and Frost Mastery drafts.",
    "roguelite_unlock_desc_family_poison": "Adds poison aura, poison shots, poison orb, and Poison Mastery drafts.",
    "roguelite_unlock_desc_family_lightning": "Adds lightning aura/orb, Chain Lightning, Conduit, and mastery drafts.",
    "roguelite_unlock_desc_family_wind": "Adds wind aura/rounds/orb, Aftershock, and Wind Mastery drafts.",
    "roguelite_unlock_desc_family_blood": "Adds lifesteal, blood weapons, Blood Pact, and Blood Mastery drafts.",
    "roguelite_unlock_desc_discount": "Relic: rerolls cost 20% less, never below 5 credits.",
    "roguelite_unlock_desc_shard": "Relic: +25% shards from cleared rooms.",
    "roguelite_unlock_desc_draft": "Relic: rerolls cost 10 fewer credits after other discounts.",
    "roguelite_unlock_desc_patch": "Relic: each floor boss heals 2 HP and grants +1 shield charge.",
    "roguelite_unlock_desc_elite": "Relic: elite rooms grant +30 credits and bonus shards.",
    "roguelite_unlock_desc_heat": "Unlocks the next Heat above the default. Heat 3 costs Cores earned on Heat 2+.",
    "roguelite_starter_ready": "READY",
    "roguelite_boss": "Boss",
    "roguelite_boss_tier": "Wave Surge",
    "roguelite_recursion": "Recursion",
    "roguelite_recursion_dmg": "PERM. DMG",
    "roguelite_level": "Lv",
    "roguelite_run_flow": "FLOOR ROUTE",
    "roguelite_combat_title": "DUNGEON FLOOR",
    "roguelite_heat_effects": "Effects",
    "roguelite_heat_unlock_first": "Heat 1 is unlocked by default.",
    "roguelite_heat_unlock_next": "Buy Heat",
    "roguelite_heat_buy_next": "Buy Heat",
    "roguelite_heat_maxed": "Heat fully unlocked",
    "roguelite_heat_unlock_rule": "Heat 1 is the default. Heat 2 and 3 add pressure, elites, faster spawns, tougher bosses, better shards, and exclusive core drops.",
    "roguelite_heat_core_rule": "Heat 2+ drops Cores. Heat 3 drops a lot more of them.",
    "roguelite_req_default": "Default",
    "roguelite_req_35_act2": "35 shards or Floor 2",
    "roguelite_req_75_act3": "75 shards or Floor 3",
    "roguelite_req_125_win": "125 shards or 1 win",
    "roguelite_req_200_heat2_endless1": "200 shards, Heat 2, or Endless 1",
    "roguelite_req_300_endless2": "300 shards or Endless 2",
    "roguelite_kit_operator": "Operator",
    "roguelite_kit_bulwark": "Bulwark",
    "roguelite_kit_arcanist": "Arcanist",
    "roguelite_kit_operator_desc": "Start with 15 credits and no preset power-up.",
    "roguelite_kit_bulwark_desc": "Start with 5 credits, +3 walls, and Fortified armor.",
    "roguelite_kit_arcanist_desc": "Start with Arcane Bullets installed and no credits.",
    "roguelite_family_core": "Core",
    "roguelite_family_shield": "Shield",
    "roguelite_family_arcane": "Arcane",
    "roguelite_family_fire": "Fire",
    "roguelite_family_frost": "Frost",
    "roguelite_family_poison": "Poison",
    "roguelite_family_lightning": "Lightning",
    "roguelite_family_wind": "Wind",
    "roguelite_family_blood": "Blood",
    "roguelite_relic_none": "None",
    "roguelite_relic_discount": "Discount Protocol",
    "roguelite_relic_shard": "Shard Magnet",
    "roguelite_relic_elite": "Elite Dividend",
    "roguelite_relic_patch": "Emergency Patch",
    "roguelite_relic_draft": "Draft Cache",
    "roguelite_no_run": "No active roguelite run.",
    "roguelite_no_profile": "No roguelite profile loaded.",
    "roguelite_beta_banner": "BETA - WORK IN PROGRESS",
    "stats_tab_roguelite": "Roguelite",
    "stats_roguelite_metrics": "ROGUELITE METRICS",
    "stats_roguelite_best_sectors": "Best Rooms",
    "stats_roguelite_runs": "Runs",
    "stats_roguelite_lifetime": "ROGUELITE LIFETIME",
    "stats_roguelite_mode": "Roguelite",

    # Enemy Names and Descriptions
    "enemy_circle_name": "Circle Chaser",
    "enemy_circle_desc": "Basic melee enemy that chases the player",
    "enemy_pentagon_name": "Pentagon Sniper",
    "enemy_pentagon_desc": "Precision ranged enemy with powerful, fast projectiles",
    "enemy_triangle_name": "Triangle Dasher",
    "enemy_triangle_desc": "Fast enemy with erratic zigzag movement and dash attacks",
    "enemy_star_name": "Star Tank",
    "enemy_star_desc": "Durable tank enemy that requires multiple hits to defeat",
    "enemy_cube_name": "Cube Shooter",
    "enemy_cube_desc": "Ranged enemy that maintains distance and fires 3-shot bursts",
    "enemy_hexagon_name": "Hexagon Warper",
    "enemy_hexagon_desc": "Teleporting enemy that shoots chaotic bullet patterns",
    "enemy_cross_name": "Cross Striker",
    "enemy_cross_desc": "Shows warning before executing spinning laser dash attack",
    "enemy_diamond_name": "Diamond Dasher",
    "enemy_diamond_desc": "Fast enemy that shoots projectiles during dash attacks",
    "enemy_octagon_name": "Octagon Sprayer",
    "enemy_octagon_desc": "Ranged enemy with high fire rate but low accuracy",
    "enemy_trickster_name": "Trickster",
    "enemy_trickster_desc": "Deceptive enemy that shows fake warnings and teleports",
    "enemy_phantom_name": "Phantom",
    "enemy_phantom_desc": "Teleporting enemy that creates fake clones to confuse",
    "enemy_sniper_name": "Sniper",
    "enemy_sniper_desc": "Deadly enemy that charges a powerful one-shot kill attack",
    "enemy_mage_name": "Mage",
    "enemy_mage_desc": "Magical enemy that summons meteorites and fires homing projectiles",

    # Boss Names and Descriptions
    "boss_1_name": "The Spiral Guardian",
    "boss_1_desc": "A mystical entity that weaves spiraling bullet patterns",
    "boss_2_name": "The Summoner King",
    "boss_2_desc": "Commands an army of minions to overwhelm foes",
    "boss_3_name": "The Meteor Striker",
    "boss_3_desc": "Rains destruction from above with devastating meteor strikes",
    "boss_4_name": "The Laser Architect",
    "boss_4_desc": "Constructs deadly laser grids and geometric death traps",
    "boss_5_name": "The Void Dancer",
    "boss_5_desc": "Blinks through reality, leaving trails of dark energy",
    "boss_6_name": "The Chain Reactor",
    "boss_6_desc": "A being of pure electricity that chains devastating arcs between targets",
    "boss_7_name": "The Orbital Commander",
    "boss_7_desc": "Commands orbital satellites that strike with astronomical precision",
    "boss_8_name": "The Berserker Juggernaut",
    "boss_8_desc": "An unstoppable force of pure rage that grows stronger as it bleeds",
    "boss_9_name": "The Prism Architect",
    "boss_9_desc": "Manipulates light itself into geometric prisons of splitting lasers",
    "boss_10_name": "The Timekeeper",
    "boss_10_desc": "Bends the flow of time itself, creating paradoxes and temporal rifts",
    "boss_11_name": "The Chaos Weaver",
    "boss_11_desc": "Weaves patterns of pure chaos, unpredictable and devastating",
    "boss_12_name": "The Omega Entity",
    "boss_12_desc": "The ultimate challenge - combines all previous boss mechanics",

    # Exit Confirm Dialog
    "confirm_quit_title": "CONFIRM QUIT",
    "confirm_exit_title": "CONFIRM EXIT",
    "confirm_quit_body": "Close TopHat-ShooterOS?",
    "confirm_exit_body": "Return to main menu?",
    "confirm_unsaved": "Unsaved progress will be lost.",
    "confirm_cancel_btn": "[ESC] CANCEL",
    "confirm_quit_btn": "[Q] QUIT",
    "confirm_exit_btn": "[Q] EXIT",
    "confirm_checkpoint_title": "CHECKPOINT AVAILABLE",
    "confirm_checkpoint_restart_body": "Restart from wave 1?",
    "confirm_checkpoint_sub": "You can still CONTINUE from your last checkpoint.",
    "confirm_restart_btn": "[R] RESTART",

    # Common
    "common_on": "ON",
    "common_off": "OFF",

    # Boss threat HUD
    "boss_threat_critical": "CRITICAL THREAT",
    "boss_threat_phase_header": "PHASE",
    "boss_threat_phase_name": "Phase",
    "boss_threat_breached": "BREACHED",
    "boss_threat_locked": "LOCKED",
    "boss_phase_firewall": "PHASE FIREWALL",
    "enemy_sealed_clear_adds": "SEALED - CLEAR ADDS",
    "enemy_overload_hold_fire": "OVERLOAD - HOLD FIRE",

    # Sandbox power-up visuals tab
    "sandbox_powerup_visuals": "Power-Up Visuals",
    "sandbox_visuals_subtitle": "Icon, rarity, and Lv.1 description preview",
    "sandbox_badge_legendary": "LEGENDARY",
    "sandbox_badge_common": "COMMON",
    "sandbox_lv1_preview": "Lv.1 preview",
    "sandbox_badge_locked": "LOCKED",
    "sandbox_powerup_locked_name": "??? Undiscovered",
    "sandbox_powerup_locked_desc": "Locked. Discover this power-up in a run to reveal its details.",
    "sandbox_enter_boss_3d": "Enter Boss #7 3D",
    "sandbox_test_3d_arena": "Test 3D Arena",

    # Advancements window
    "adv_control_title": "ADVANCEMENT CONTROL",
    "adv_sync_desc": "Persistent progression synced from lifetime stats, last runs, and roguelite profile data. Claim unlocks to bank Data Shards.",
    "adv_unlocked_count": "Unlocked",
    "adv_claimed_count": "Claimed",
    "adv_shard_balance": "Data Shards",
    "adv_claim_all": "Claim All +",
    "adv_all_claimed": "All Claimed",
    "adv_categories": "Categories",
    "adv_detail": "Detail",
    "adv_progress": "Progress",
    "adv_status": "Status",
    "adv_reward": "Reward",
    "adv_unlocked_at": "Unlocked",
    "adv_reward_claimed": "Reward Claimed",
    "adv_claim_reward": "Claim Reward",
    "adv_locked_btn": "Locked",
    "adv_tier_legend": "Rarity",
    "adv_category_label": "Category",

    # Stats window leftovers
    "stats_healing_sources": "Healing Sources",
    "stats_health_consumable": "Health Consumable",
    "stats_no_healing_data": "No healing data",
    "stats_total_earned": "Total Earned",
    "stats_analytics_report": "System Analytics - Run Report",

    # Desktop
    "desktop_net": "NET",
    "desktop_advancement_unlocked": "Advancement unlocked",
    "desktop_mode_locked": "MODE LOCKED:",
    "survival_locked_desc": "Unlock Time Survival by beating Roguelite mode.",
    "roguelite_locked_desc": "Unlock Roguelite by defeating the Wave 20 boss in Wave Mode.",
    "game_mode_unlocked": "NEW MODE UNLOCKED:",
    "roguelite_unlocked_notif": "Roguelite Mode is now available on the desktop!",
    "survival_unlocked_notif": "Time Survival Mode is now available on the desktop!",

    # Debug panel runtime stats
    "debug_panel_dps": "DPS",
    "debug_panel_cmin": "C/min",
    "debug_panel_abilities": "ABILITIES",

    # Cheat / debug menu (new keys)
    "cheat_lv": "Lv",
    "cheat_remove": "Remove",
    "cheat_alive": "alive",
    "cheat_of": "of",
    "cheat_more_enemies": "more enemies...",
    "cheat_custom_boss": "CUSTOM BOSS",
    "cheat_enemy_environment": "Environment",
    "cheat_cons_health": "Health",
    "cheat_cons_coin": "Coin",
    "cheat_cons_shield": "Shield Boost",
    "cheat_cons_damage": "Damage Boost",
    "cheat_cons_double_coin": "Double Coin",
    "cheat_cons_lifesteal": "Lifesteal",

    # Comeback mechanic
    "comeback_bonus_active": "COMEBACK +10%",
    "comeback_bonus_until": "until wave",

    # Settings
    "settings_replay_mode_intros": "Replay Mode Intros",

    # Mode intro: wave-based (Act 1-2 live open; the ending archive is
    # "ARCHIVE PLAYBACK // INCIDENT RESOLVED", this is the same incident, live)
    "mode_intro_wave_title": "LIVE DISPATCH // THREAT RESPONSE",
    "mode_intro_wave_rec1":  "RADAR SWEEP",
    "mode_intro_wave_1a":    "THE BREACH IS OPEN. THE FLOOD POURS IN.",
    "mode_intro_wave_1b":    "WAVE-DEFENSE PROTOCOL ACTIVATED",
    "mode_intro_wave_rec2":  "DEPLOYMENT",
    "mode_intro_wave_2a":    "EVERY WAVE LEARNS. EVERY WAVE GETS CLOSER.",
    "mode_intro_wave_2b":    "HOLD THE LINE, OPERATOR.",

    # Mode intro: time survival (Act 4 live open of "THE LONG WATCH")
    "mode_intro_surv_title": "LIVE DISPATCH // THE LONG WATCH",
    "mode_intro_surv_rec1":  "COUNTDOWN",
    "mode_intro_surv_1a":    "THE ROOT IS PURGED. THE FLOOD STILL COMES.",
    "mode_intro_surv_1b":    "THE LONG WATCH BEGINS.",
    "mode_intro_surv_rec2":  "UPTIME LOG",
    "mode_intro_surv_2a":    "EVERY SECOND OF UPTIME IS LOGGED.",
    "mode_intro_surv_2b":    "NO RELIEF IS COMING. HOLD ANYWAY.",

    # Mode intro: roguelite (Act 3 live open of "DEEP RECOVERY")
    "mode_intro_rogue_title": "LIVE DISPATCH // DEEP RECOVERY",
    "mode_intro_rogue_rec1":  "STACK MAP",
    "mode_intro_rogue_1a":    "THE SURFACE IS SECURE. THE ROT STILL PULSES BELOW.",
    "mode_intro_rogue_1b":    "DESCEND THE STACK, SECTOR BY SECTOR.",
    "mode_intro_rogue_rec2":  "RELIC SCAN",
    "mode_intro_rogue_2a":    "RECOVER LOST KERNEL PROCESSES. CLAIM RELICS.",
    "mode_intro_rogue_2b":    "FIND WHAT THE ROOT GREW FROM.",

    # Mode intro: sandbox (non-canon, outside the incident archive)
    "mode_intro_sandbox_title": "OFF THE RECORD // TEST ENVIRONMENT",
    "mode_intro_sandbox_rec1":  "INIT SEQUENCE",
    "mode_intro_sandbox_1a":    "TEST ENVIRONMENT ACTIVE",
    "mode_intro_sandbox_1b":    "WARNING: NO GUARDRAILS. PROCEED FREELY.",

    # Mode intro: pvp (non-canon, outside the incident archive)
    "mode_intro_pvp_title": "EXTERNAL FEED // HOSTILE NODE",
    "mode_intro_pvp_rec1":  "NETWORK SCAN",
    "mode_intro_pvp_1a":    "HOSTILE NODE DETECTED",
    "mode_intro_pvp_1b":    "MULTI-AGENT CONFLICT PROTOCOL ENGAGED",
    "mode_intro_pvp_rec2":  "ADVERSARY LOCK",
    "mode_intro_pvp_2a":    "ADVERSARY SIGNATURE CONFIRMED",
    "mode_intro_pvp_2b":    "ELIMINATE OR BE ELIMINATED.",
    # Mode-exclusive power-up names
    "powerup_glitch_field":    "GLITCH_FIELD.dll",
    "powerup_time_surge":      "TIME_SURGE.exe",
    "powerup_last_stand":      "LAST_STAND.sys",
    "powerup_recursion":       "RECURSION.bin",
    "powerup_sector_protocol": "SECTOR_PROTOCOL.exe",
    # Mode-exclusive power-up descriptions
    "powerup_glitch_field_desc1":   "Bullets have a 20% chance to scramble enemy navigation for 0.5s.",
    "powerup_glitch_field_desc2":   "Bullets have a 30% chance to scramble enemy navigation for 0.5s.",
    "powerup_glitch_field_desc3":   "Bullets have a 40% chance to scramble enemy navigation for 0.5s.",
    "powerup_time_surge_desc1":     "Each kill extends your fire rate boost timer by 0.5s.",
    "powerup_time_surge_desc2":     "Each kill extends your fire rate boost timer by 0.75s.",
    "powerup_time_surge_desc3":     "Each kill extends your fire rate boost timer by 1s.",
    "powerup_last_stand_desc":      "LEGENDARY: Once per life, surviving a killing blow grants 3s of invulnerability.",
    "powerup_recursion_desc1":      "+8% permanent damage.",
    "powerup_recursion_desc2":      "+14% permanent damage.",
    "powerup_recursion_desc3":      "+20% permanent damage.",
    "powerup_sector_protocol_desc": "LEGENDARY: Each kill grants +1 coin. Each new floor grants +15 coins.",
    # Stage 5 survival-exclusive names
    "powerup_crisis_mode":          "CRISIS_MODE.dll",
    "powerup_adaptive_firewall":    "ADAPT_FW.exe",
    "powerup_last_transmission":    "LAST_TX.dll",
    "powerup_kill_chain":           "KILLCHAIN.exe",
    # Stage 5 survival-exclusive descriptions
    "powerup_crisis_mode_desc1":    "Below 30% HP: deal +15% bonus damage.",
    "powerup_crisis_mode_desc2":    "Below 30% HP: deal +20% bonus damage.",
    "powerup_crisis_mode_desc3":    "Below 30% HP: deal +25% bonus damage.",
    "powerup_adaptive_firewall_desc1": "Taking a hit grants 3s of +25% fire rate.",
    "powerup_adaptive_firewall_desc2": "Taking a hit grants 3s of +35% fire rate.",
    "powerup_adaptive_firewall_desc3": "Taking a hit grants 3s of +45% fire rate.",
    "powerup_last_transmission_desc1": "12% chance per kill to restore 0.5 HP.",
    "powerup_last_transmission_desc2": "18% chance per kill to restore 0.5 HP.",
    "powerup_last_transmission_desc3": "25% chance per kill to restore 0.5 HP.",
    "powerup_kill_chain_desc":      "LEGENDARY: 5 kills within 3s triggers a 1.5x damage shockwave.",
    # Stage 5 roguelite-exclusive names
    "powerup_corrupted_core":       "CORRUPT_CORE.dll",
    "powerup_room_echo":            "ROOM_ECHO.dll",
    "powerup_chain_reaction":       "CHAIN_REACT.dll",
    "powerup_kernel_exploit":       "KERNEL_EXPLOIT.sys",
    # Stage 5 roguelite-exclusive descriptions
    "powerup_corrupted_core_desc1": "Elite kills grant +100 max HP.",
    "powerup_corrupted_core_desc2": "Elite kills grant +150 max HP.",
    "powerup_corrupted_core_desc3": "Elite kills grant +200 max HP.",
    "powerup_room_echo_desc1":      "Room clear grants 8 charged bullets dealing +60% damage.",
    "powerup_room_echo_desc2":      "Room clear grants 12 charged bullets dealing +60% damage.",
    "powerup_room_echo_desc3":      "Room clear grants 16 charged bullets dealing +60% damage.",
    "powerup_chain_reaction_desc1": "20% chance per kill to drop a bonus coin.",
    "powerup_chain_reaction_desc2": "30% chance per kill to drop a bonus coin.",
    "powerup_chain_reaction_desc3": "40% chance per kill to drop a bonus coin.",
    "powerup_kernel_exploit_desc":  "LEGENDARY: Defeating a boss grants +20% permanent damage.",
    "powerup_data_harvest":         "DATA_HARVEST.dll",
    "powerup_data_harvest_desc1":   "Enemies grant +25% XP. +25% pickup range.",
    "powerup_data_harvest_desc2":   "Enemies grant +50% XP. +50% pickup range.",
    "powerup_data_harvest_desc3":   "Enemies grant +100% XP. +100% pickup range.",
    "resume_run_title":        "SAVED RUN FOUND",
    "resume_run_body":         "Continue your saved run or start a new one?",
    "resume_continue":         "CONTINUE",
    "resume_new_run":          "NEW RUN",
    "new_process_installed":   "NEW PROCESS DISCOVERED"
  }.toTable,

  Spanish: {
    # Main Menu
    "menu_play": "jugar",
    "menu_survival": "supervivencia",
    "menu_stats": "estadísticas",
    "menu_help": "ayuda",
    "menu_settings": "config",
    "menu_quit": "salir",
    "menu_sandbox": "sandbox",

    # Desktop icons
    "desktop_icon_play": "WAVE0.exe",
    "desktop_icon_survival": "LASTSTAND.exe",
    "desktop_icon_stats": "REGS.dat",
    "desktop_icon_settings": "CONFIG.sys",
    "desktop_icon_help": "MANUAL.exe",
    "desktop_icon_quit": "APAGAR.exe",
    "desktop_icon_sandbox": "LAB.exe",
    "desktop_icon_shop": "CROMAS.db",
    "desktop_icon_pvp": "DUELOS.exe",
    "desktop_icon_roguelite": "ROOTMAP_ALPHA.db",
    "desktop_icon_advancements": "ASCEND.db",
    "desktop_icon_changelog": "PARCHES.txt",
    "desktop_icon_credits": "CREDITOS.nfo",

    # Credits window
    "credits_window_title": "Creditos - Acerca de",
    "credits_header": "Creditos",
    "credits_role": "Diseno y Programacion",
    "credits_built_with": "Hecho Con",
    "credits_thanks": "Gracias",
    "credits_thanks_body": "A todos los que jugaron, reportaron errores y sugirieron ideas.",
    "credits_license": "Bajo licencia Apache 2.0",
    "support_title": "Apoya el Proyecto",
    "support_blurb": "TopHat-ShooterOS es gratuito y de codigo abierto. Apoyar es opcional y nunca bloquea ninguna funcion.",
    "support_note": "Los enlaces se abren en tu navegador.",

    # Changelog window
    "changelog_window_title": "Notas del Parche - Cambios",
    "changelog_header": "Novedades",
    "changelog_since": "Cambios desde v5.5.2",
    "changelog_latest": "RECIENTE",
    "changelog_cat_new": "Nuevo",
    "changelog_cat_improved": "Mejoras",
    "changelog_cat_balance": "Balance",
    "changelog_cat_fixed": "Correcciones",

    # Settings
    "settings_title": "CONFIG",
    "settings_fps_limit": "Límite FPS:",
    "settings_click_edit": "Clic: editar, Enter: confirmar",
    "settings_sound_effects": "Efectos:",
    "settings_music": "Música:",
    "settings_sound_effects_desc": "(explosiones, UI, efectos en juego)",
    "settings_music_desc": "(volumen de música de fondo)",
    "settings_fullscreen": "Pantalla:",
    "settings_fullscreen_toggle": "(F11 para cambiar)",
    "settings_render_resolution": "Resolución mejorada (SSAA):",
    "settings_render_resolution_desc": "(mejora la nitidez en pantalla completa)",
    "settings_render_resolution_disabled": "Desactivada",
    "settings_render_resolution_enabled": "Activada",
    "settings_render_resolution_fullscreen_only": "Solo pantalla completa",
    "settings_vsync": "VSync:",
    "settings_vsync_desc": "(bloquea FPS al refresco del monitor)",
    "settings_show_fps": "Mostrar FPS:",
    "settings_mouse_support": "Ratón:",
    "settings_mouse_support_desc": "(navegación de menú)",
    "settings_mouse_bonding": "Bloqueo del ratón:",
    "settings_mouse_bonding_desc": "(clic para cambiar el modo)",
    "settings_mouse_bonding_off": "Apagado",
    "settings_mouse_bonding_while_shooting": "Al disparar",
    "settings_mouse_bonding_always_in_game": "Siempre en partida",
    "settings_mouse_bonding_always": "Siempre",
    "settings_show_cursor": "Cursor:",
    "settings_show_cursor_desc": "(solo visual)",
    "settings_debug_panel": "Debug:",
    "settings_debug_panel_desc": "(stats arriba-derecha)",
    "settings_arena_vignette": "Viñeta Arena:",
    "settings_arena_vignette_desc": "(sombreado oscuro en bordes)",
    "settings_low_health_vignette": "Viñeta HP Bajo:",
    "settings_low_health_vignette_desc": "(aviso rojo con poca vida)",
    "settings_show_hints": "Consejos:",
    "settings_show_hints_desc": "(E: Muro, ESC: Pausa)",
    "settings_hud_layout": "Diseño del HUD:",
    "settings_hud_layout_desc": "(Panorámico añade paneles laterales)",
    "settings_hud_layout_classic": "Clásico (4:3)",
    "settings_hud_layout_widescreen": "Panorámico (16:9)",
    "settings_show_enemy_labels": "Etiquetas:",
    "settings_show_enemy_labels_desc": "(nombres sobre enemigos)",
    "settings_exit_confirm": "Confirmar Salida:",
    "settings_exit_confirm_desc": "(aviso al salir del juego)",
    "settings_language": "Idioma:",
    "settings_replay_intro": "Volver a ver intro",
    "settings_replay_ending": "Volver a ver final",
    "settings_replay_roguelite_ending": "Volver a ver roguelite",
    "settings_replay_survival_ending": "Volver a ver supervivencia",
    "settings_replay_wave_intro": "Intro Oleadas",
    "settings_replay_survival_intro": "Intro Supervivencia",
    "settings_replay_roguelite_intro": "Intro Roguelite",
    "settings_replay_sandbox_intro": "Intro Sandbox",
    "settings_replay_pvp_intro": "Intro JcJ",
    "settings_back_to_menu": "ESC para volver",

    "lore_title_card_sub": "REPRODUCCIÓN DE ARCHIVO // INCIDENTE",
    "lore_live": "EN VIVO",
    "lore_playback": "PLAY",
    "lore_controls_ff": "ENTER: X2  |  ESPACIO: SALTAR",
    "lore_controls_ff_active": "ENTER: X2 ACTIVO  |  ESPACIO: SALTAR",
    "lore_rec_breach": "REC 00: BRECHA DEL SISTEMA",
    "lore_rec_swarm": "REC 01: AVALANCHA DE PROCESOS",
    "lore_rec_awaken": "REC 02: DESPERTAR DEL KERNEL",
    "lore_rec_boss": "REC 03: LA RAÍZ",
    "lore_rec_counter": "REC 04: BUCLE DE DEFENSA",
    "lore_rec_directive": "REC 05: TRASPASO DE PROTOCOLO",
    "lore_breach_1": "Un servidor desconocido fuerza la puerta de TopHat-ShooterOS.",
    "lore_breach_2": "La puerta es solo eso. Algo la cruzó.",
    "lore_swarm_1": "Su corrupción irrumpe: formas, fragmentos y hambre.",
    "lore_swarm_2": "Cada oleada aprende. Cada oleada se acerca.",
    "lore_awaken_1": "TOPHAT despierta y arranca su último proceso fiable: tú.",
    "lore_awaken_2": "El kernel no puede luchar confinado. Tú sí.",
    "lore_boss_1": "Lo que cruzó la brecha es más antiguo que el SO.",
    "lore_boss_2": "Corre como root y escribe cada ataque que enfrentas.",
    "lore_counter_1": "Tu fuego son parches. Sus fragmentos, poder.",
    "lore_counter_2": "El sistema aún puede salvarse.",
    "lore_directive_title": "PROTOCOLO DE DEFENSA: ACTIVO",
    "lore_directive_sub": "Aguanta la línea, operador.",

    "end_title_card_sub": "REPRODUCCIÓN DE ARCHIVO // INCIDENTE RESUELTO",
    "end_rec_fall": "REC 06: LA RAÍZ PURGADA",
    "end_rec_purge": "REC 07: MEMORIA RECUPERADA",
    "end_rec_restore": "REC 08: KERNEL RESTAURADO",
    "end_rec_crown": "REC 09: ACCESO ROOT CONCEDIDO",
    "end_rec_signoff": "REC 10: PROTOCOLO COMPLETO",
    "end_fall_1": "La Raíz se hace pedazos.",
    "end_fall_2": "Su código se deshace de vuelta por la brecha de la que surgió.",
    "end_purge_1": "La corrupción retrocede, sector a sector.",
    "end_purge_2": "Tras ella se recupera memoria limpia.",
    "end_restore_1": "Kernel TOPHAT restaurado. Contención estable.",
    "end_restore_2": "Nivel de amenaza bajando... cero.",
    "end_crown_1": "Con la Raíz eliminada, su acceso root pasa a ti.",
    "end_crown_2": "Ahora llevas la corona del kernel.",
    "end_signoff_title": "SISTEMA ASEGURADO",
    "end_signoff_sub": "Nivel de amenaza cero. Descansa: te has ganado la corona.",

    "rog_end_title_card_sub": "REPRODUCCIÓN DE ARCHIVO // RECUPERACIÓN PROFUNDA",
    "rog_end_rec_descend": "DESCENSO 01: BAJADA DE SECTOR",
    "rog_end_rec_core": "DESCENSO 02: NÚCLEO CORRUPTO",
    "rog_end_rec_extract": "DESCENSO 03: EXTRACCIÓN DE DATOS",
    "rog_end_rec_reveal": "DESCENSO 04: ORIGEN EXPUESTO",
    "rog_end_rec_ascend": "DESCENSO 05: SUBIDA DE PILA",
    "rog_end_rec_signoff": "DESCENSO 06: SUPERFICIE ALCANZADA",
    "rog_end_descend_1": "La superficie quedó asegurada, pero la podredumbre aún latía abajo.",
    "rog_end_descend_2": "Ya coronado, descendiste a acabarla en su origen.",
    "rog_end_core_1": "En el fondo de la recursión aguardaba la semilla-",
    "rog_end_core_2": "el núcleo del que nació la Raíz, más antiguo que el propio TOPHAT.",
    "rog_end_extract_1": "Arrancaste la semilla, fragmento a fragmento,",
    "rog_end_extract_2": "y el bucle sin fin comenzó a deshacerse.",
    "rog_end_reveal_1": "En la última luz de la semilla viste la verdad:",
    "rog_end_reveal_2": "la brecha no trajo a la Raíz. La despertó.",
    "rog_end_ascend_1": "Subiste por la pila que se derrumbaba,",
    "rog_end_ascend_2": "con los núcleos recuperados ardiendo en la mano.",
    "rog_end_signoff_title": "SECTOR DESPEJADO",
    "rog_end_signoff_sub": "La recursión está rota, pero ahora sabes cuán hondo llega root.",

    "sur_end_title_card_sub": "REPRODUCCIÓN DE ARCHIVO // LA LARGA VIGILIA",
    "sur_end_rec_watch": "REG 01: LA LARGA VIGILIA",
    "sur_end_rec_surge": "REG 02: OLEADA FINAL",
    "sur_end_rec_fall": "REG 03: SEÑAL PERDIDA",
    "sur_end_rec_shutdown": "REG 04: SISTEMA DETENIDO",
    "sur_end_rec_signoff": "REG 05: FIN DEL ARCHIVO",
    "sur_end_watch_1": "Mucho después de la Raíz, mucho después de la corona, mantuviste la vigilia.",
    "sur_end_watch_2": "La marea nunca terminó. Solo esperaba.",
    "sur_end_surge_1": "Pero la marea nunca se cansó como tú.",
    "sur_end_surge_2": "La última oleada halló la brecha que no pudiste cerrar.",
    "sur_end_fall_1": "Tu proceso se atenuó y luego se apagó.",
    "sur_end_fall_2": "Y esta vez, ningún reinicio respondió.",
    "sur_end_shutdown_1": "Una a una, las luces del kernel se apagaron.",
    "sur_end_shutdown_2": "TopHat-ShooterOS dejó de responder.",
    "sur_end_signoff_title": "SISTEMA DETENIDO",
    "sur_end_signoff_sub": "La larga vigilia terminó. La pantalla sigue a oscuras.",

    "settings_section_data_management": "DATOS",
    "settings_reset_all_data": "Reiniciar todo",
    "settings_reset_advancements": "Reiniciar avances",
    "settings_reset_roguelite_data": "Reiniciar roguelite",
    "settings_confirm_reset": "Confirmar",
    "settings_reset_complete": "Reinicio completo",
    "settings_reset_failed": "Error al reiniciar",

    # Settings window tabs and sections
    "settings_tab_graphics": "Gráficos",
    "settings_tab_audio": "Audio",
    "settings_tab_controls": "Controles",
    "settings_tab_gameplay": "Juego",
    "settings_tab_cinematics": "Cinemáticas",

    "settings_section_story": "CINEMÁTICAS DE HISTORIA",
    "settings_section_mode_intros": "INTROS DE MODO",
    "settings_section_display": "PANTALLA",
    "settings_section_volume_control": "VOLUMEN",
    "settings_section_input_method": "ENTRADA",
    "settings_section_assistance": "ASISTENCIA",
    "settings_section_localization": "IDIOMA",
    "settings_section_keyboard_shortcuts": "ATAJOS",

    "settings_keyboard_wasd": "WASD / Flechas",
    "settings_keyboard_movement": "Movimiento",
    "settings_keyboard_mouse_space": "Ratón / Espacio",
    "settings_keyboard_shoot": "Disparar",
    "settings_keyboard_e": "E",
    "settings_keyboard_place_wall": "Muro",
    "settings_keyboard_q": "Q",
    "settings_keyboard_legendary_abilities": "Habs. Legend.",
    "settings_keyboard_esc": "ESC",
    "settings_keyboard_pause_menu": "Pausa / Menú",
    "settings_keyboard_f11": "F11",
    "settings_keyboard_toggle_fullscreen": "P. Completa",
    "settings_keyboard_tab": "Tab",

    # Rebindable keybinds UI (Spanish)
    "settings_section_keybindings": "CONTROLES",
    "keybind_move_up": "Mover Arriba",
    "keybind_move_down": "Mover Abajo",
    "keybind_move_left": "Mover Izquierda",
    "keybind_move_right": "Mover Derecha",
    "keybind_shoot": "Disparar",
    "keybind_place_wall": "Colocar Muro / Interactuar",
    "keybind_legendary": "Habilidad Legendaria",
    "keybind_press_any_key": "Pulsa cualquier tecla...",
    "keybind_reset_defaults": "Restaurar Valores",
    "keybind_non_rebindable_note": "ESC: Pausa  |  F11: Pantalla completa  (fijos)",
    "gamepad_column_key": "Tecla",
    "gamepad_column_pad": "Mando",
    "gamepad_press_any_button": "Pulsa un boton...",
    "gamepad_reserved_note": "Mando: A = clic, B = atras, Start = pausa (fijos)",
    "settings_aim_assist": "Asistencia de Apuntado",
    "settings_aim_assist_desc": "El apuntado con mando se ajusta a enemigos cercanos",
    "settings_controller": "Mando",
    "settings_controller_desc": "Que mando detectado controla el juego",
    "settings_controller_auto": "Auto (primero detectado)",
    "settings_controller_none": "Ningun mando detectado",

    # Game UI
    "game_pause": "PAUSA",
    "game_resume": "Continuar",
    "game_restart": "Reiniciar",
    "game_main_menu": "Menú Principal",
    "game_over": "FIN DEL JUEGO",
    "game_score": "Puntuación:",
    "game_wave": "Oleada",
    "game_health": "Vida:",
    "game_coins": "Monedas:",
    "game_status": "ESTADO",
    "game_wave_info": "Info de Oleada:",
    "game_active": "Activo",
    "game_boss": "JEFE",
    "game_boss_fight": "OLEADA DE JEFE",
    "game_collect": "Recoger",
    "game_left": "restantes",
    "game_charges": "Cargas",
    "game_processes": "Procesos",

    # Shop/Powerups
    "shop_title": "TIENDA",
    "shop_buy": "Comprar",
    "shop_upgrade": "Mejorar",
    "shop_cost": "Costo:",
    "shop_owned": "Comprado",
    "shop_credit_store": "TIENDA - MEJORAS",
    "shop_upgrades_available": "MEJORAS",
    "shop_active_upgrades": "ACTIVAS",
    "shop_available_purchases": "DISPONIBLES:",
    "shop_controls": "CONTROLES:",
    "shop_navigate": "Navegar",
    "shop_continue": "Continuar",
    "shop_buy_selected": "COMPRAR",
    "shop_insufficient_credits": "SIN FONDOS",
    "shop_no_permanent": "Sin mejoras aún.",
    "shop_defeat_waves": "¡Derrota oleadas!",
    "shop_credits": "CR",
    "shop_bought": "Comprado",
    "shop_damage_plus": "Daño +",
    "shop_damage_plus_desc": "Mejora de daño",
    "shop_fire_rate_plus": "Cadencia +",
    "shop_fire_rate_plus_desc": "Mejora de cadencia",
    "shop_move_speed_plus": "Velocidad +",
    "shop_move_speed_plus_desc": "Mejora de velocidad",
    "shop_max_health_plus": "Vida Máx +",
    "shop_max_health_plus_desc": "Aumento de vida",
    "shop_bullet_speed_plus": "Vel. Balas +",
    "shop_bullet_speed_plus_desc": "Mejora de balas",
    "shop_wall_x4": "Muro (x10)",
    "shop_wall_x4_desc": "Compra 10 muros desplegables",

    # Powerup Names
    "powerup_double_shot": "Disparo Doble",
    "powerup_rotating_shield": "Escudo Giratorio",
    "powerup_magical_bullets": "Balas Mágicas",
    "powerup_piercing_shots": "Disparos Perforantes",
    "powerup_multi_shot": "Multidisparo",
    "powerup_explosive_bullets": "Balas Explosivas",
    "powerup_life_steal": "Robo de Vida",
    "powerup_rapid_fire": "Sobrecarga",
    "powerup_max_health": "Coloso",
    "powerup_speed_boost": "Impulso",
    "powerup_bullet_speed": "Lightspeed",
    "powerup_lucky_coins": "Codicia",
    "powerup_wall_master": "Maestro de Muros",
    "powerup_regeneration": "Regeneración",
    "powerup_dodge_chance": "Evasión",
    "powerup_critical_hit": "Golpe Crítico",
    "powerup_blood_bullets": "Balas de Sangre",
    "powerup_bullet_ricochet": "Rebote",
    "powerup_slow_field": "Campo Lento",
    "powerup_rage": "Furia",
    "powerup_berserker": "Berserker",
    "powerup_thorns": "Espinas",
    "powerup_bullet_split": "Disparo Dividido",
    "powerup_chain_lightning": "Rayo en Cadena",
    "powerup_frost_shots": "Disparos Helados",
    "powerup_poison_shot": "Disparos Venenosos",
    "powerup_fire_bullets": "Balas de Fuego",
    "powerup_wind_bullets": "Balas de Viento",
    "powerup_fire_aura": "Aura de Fuego",
    "powerup_lightning_aura": "Aura de Rayo",
    "powerup_poison_aura": "Aura Venenosa",
    "powerup_wind_aura": "Aura de Viento",
    "powerup_time_warp": "Cronos",
    "powerup_gravity_well": "Singularidad",
    "powerup_phase_shift": "Cambio de Fase",
    "powerup_overcharge": "Sobrecarga",
    "powerup_echo_shots": "Disparos de Eco",
    "powerup_rotating_orbs": "Orbes Elementales",
    "powerup_poison_orb": "Orbes Venenosos",
    "powerup_fire_orb": "Orbes de Fuego",
    "powerup_lightning_orb": "Orbes de Rayo",
    "powerup_wind_orb": "Orbes de Viento",
    "powerup_frost_orb": "Orbes Helados",
    "powerup_arcane_bullets": "Balas Arcanas",
    "powerup_arcane_aura": "Aura Arcana",
    "powerup_arcane_orb": "Orbes Arcanos",
    "powerup_fire_mastery": "Dominio del Fuego",
    "powerup_poison_mastery": "Dominio del Veneno",
    "powerup_frost_mastery": "Dominio de Escarcha",
    "powerup_arcane_mastery": "Dominio Arcano",
    "powerup_lightning_mastery": "Dominio del Rayo",
    "powerup_wind_mastery": "Dominio del Viento",
    "powerup_parry": "Parada",
    "powerup_blood_orb": "Orbes de Sangre",
    "powerup_blood_aura": "Aura de Sangre",
    "powerup_blood_mastery": "Señor de Sangre",
    "powerup_radial_burst": "Ráfaga Radial",
    "powerup_wall_turrets": "Centinelas de Muro",
    "powerup_pulse_armor": "Armadura de Pulso",
    "powerup_heavy_rounds": "Balas Pesadas",
    "powerup_fortified": "Fortificado",
    "powerup_special_rounds": "Balas Especiales",
    "powerup_giant_slayer": "Matador de Gigantes",
    "powerup_curse": "Maldición",
    "powerup_celestial_veil": "Velo Celestial",

    # Powerup Descriptions
    "powerup_double_shot_desc": "Disparar ráfaga adicional después de 0.08s (-15% daño por bala, -25% cadencia)",
    "powerup_rotating_shield_desc1": "3 escudos (30% cobertura, 100 HP, 6s reaparición)",
    "powerup_rotating_shield_desc2": "3 escudos (35% cobertura, 250 HP, 5s reaparición)",
    "powerup_rotating_shield_desc3": "3 escudos (40% cobertura, 400 HP, 3s reaparición)",
    "powerup_magical_bullets_desc": "Las balas rastrean al enemigo más cercano",
    "powerup_piercing_shots_desc1": "Balas perforan 1 enemigo (-33% daño por perforación)",
    "powerup_piercing_shots_desc2": "Balas perforan 2 enemigos (-33% daño por perforación)",
    "powerup_piercing_shots_desc3": "Balas perforan 3 enemigos (-33% daño por perforación)",
    "powerup_multi_shot_desc": "Dispara en 3 direcciones (-30% daño por bala)",
    "powerup_explosive_bullets_desc1": "Balas explotan (50% daño bala, radio pequeño)",
    "powerup_explosive_bullets_desc2": "Balas explotan (50% daño bala, radio mediano)",
    "powerup_explosive_bullets_desc3": "Balas explotan (50% daño bala, radio grande)",
    "powerup_life_steal_desc1": "Restaura 100 HP cada 10 bajas",
    "powerup_life_steal_desc2": "Restaura 100 HP cada 7 bajas",
    "powerup_life_steal_desc3": "Restaura 100 HP cada 5 bajas",
    "powerup_rapid_fire_desc": "Sobrecarga: mantén el disparo para acelerar la cadencia hasta +30%",
    "powerup_max_health_desc": "Coloso: +2% de daño por cada 100 HP máx, incluyendo HP base (máx +40%)",
    "powerup_speed_boost_desc": "Impulso: hasta +25% de daño en movimiento",
    "powerup_bullet_speed_desc": "Lightspeed: cada disparo lanza un rayo trazador instantáneo que golpea al primer enemigo en línea por 50% de daño",
    "powerup_lucky_coins_desc": "Duplica todas las monedas recogidas",
    "powerup_wall_master_desc": "Los muros ganan +250% de HP y las torretas +100% de daño",
    "powerup_regeneration_desc1": "Regenera 150 HP + 3% de vida máxima por oleada",
    "powerup_regeneration_desc2": "Regenera 250 HP + 5% de vida máxima por oleada",
    "powerup_regeneration_desc3": "Regenera 350 HP + 7% de vida máxima por oleada",
    "powerup_dodge_chance_desc1": "15% de probabilidad de esquivar golpes",
    "powerup_dodge_chance_desc2": "20% de probabilidad de esquivar golpes",
    "powerup_dodge_chance_desc3": "30% de probabilidad de esquivar golpes",
    "powerup_critical_hit_desc1": "20% probabilidad de 2x daño (todas fuentes)",
    "powerup_critical_hit_desc2": "35% probabilidad de 2x daño (todas fuentes)",
    "powerup_critical_hit_desc3": "50% probabilidad de 2x daño (todas fuentes)",
    "powerup_blood_bullets_desc1": "Restaura 1 HP + 0.75% del daño de bala (sangre)",
    "powerup_blood_bullets_desc2": "Restaura 1 HP + 1% del daño de bala (sangre)",
    "powerup_blood_bullets_desc3": "Restaura 1 HP + 1.375% del daño de bala (sangre)",
    "powerup_bullet_ricochet_desc1": "Balas rebotan 1 vez (50% daño por rebote)",
    "powerup_bullet_ricochet_desc2": "Balas rebotan 2 veces (50% daño por rebote)",
    "powerup_bullet_ricochet_desc3": "Balas rebotan 3 veces (50% daño por rebote)",
    "powerup_slow_field_desc1": "Pulso: ralentiza un 30% en radio 288",
    "powerup_slow_field_desc2": "Pulso: ralentiza un 45% en radio 374",
    "powerup_slow_field_desc3": "Pulso: ralentiza un 55% en radio 460",
    "powerup_rage_desc1": "+5% daño por 10% HP perdido",
    "powerup_rage_desc2": "+8% daño por 10% HP perdido",
    "powerup_rage_desc3": "+12% daño por 10% HP perdido",
    "powerup_berserker_desc1": "+5% cadencia por 10% HP perdido",
    "powerup_berserker_desc2": "+8% cadencia por 10% HP perdido",
    "powerup_berserker_desc3": "+12% cadencia por 10% HP perdido",
    "powerup_thorns_desc1": "Refleja el 100% del daño al atacante",
    "powerup_thorns_desc2": "Refleja el 200% del daño al atacante",
    "powerup_thorns_desc3": "Refleja el 300% del daño al atacante",
    "powerup_bullet_split_desc1": "Las balas se dividen en 2 fragmentos que solo hacen daño",
    "powerup_bullet_split_desc2": "Las balas se dividen en 3 fragmentos que solo hacen daño",
    "powerup_bullet_split_desc3": "Las balas se dividen en 4 fragmentos que solo hacen daño",
    "powerup_chain_lightning_desc1": "Golpe encadena a 1 enemigo (70% daño bala, rango 120, aturdimiento 0.05s)",
    "powerup_chain_lightning_desc2": "Golpe encadena a 2 enemigos (85% daño bala, rango 140, aturdimiento 0.05s)",
    "powerup_chain_lightning_desc3": "Golpe encadena a 3 enemigos (100% daño bala, rango 160, aturdimiento 0.05s)",
    "powerup_frost_shots_desc1": "Balas ralentizan enemigos 25% (permanente)",
    "powerup_frost_shots_desc2": "Balas ralentizan enemigos 40% (permanente)",
    "powerup_frost_shots_desc3": "Balas ralentizan enemigos 60% (permanente)",
    "powerup_poison_shot_desc1": "Balas envenenan ({0} daño/s, 4s, acumulable)",
    "powerup_poison_shot_desc2": "Balas envenenan ({0} daño/s, 5s, acumulable)",
    "powerup_poison_shot_desc3": "Balas envenenan ({0} daño/s, 6s, acumulable)",
    "powerup_fire_bullets_desc1": "Balas queman ({0} daño/s, 2s)",
    "powerup_fire_bullets_desc2": "Balas queman ({0} daño/s, 3s)",
    "powerup_fire_bullets_desc3": "Balas queman ({0} daño/s, 4s)",
    "powerup_wind_bullets_desc1": "Balas empujan enemigos (empuje débil, +50 de daño)",
    "powerup_wind_bullets_desc2": "Balas empujan enemigos (empuje medio, +50 de daño)",
    "powerup_wind_bullets_desc3": "Balas empujan enemigos (empuje fuerte, +50 de daño)",
    "powerup_fire_aura_desc1": "Pulso de fuego {0} daño/s en radio 238 (2s)",
    "powerup_fire_aura_desc2": "Pulso de fuego {0} daño/s en radio 309 (3s)",
    "powerup_fire_aura_desc3": "Pulso de fuego {0} daño/s en radio 380 (4s)",
    "powerup_lightning_aura_desc1": "Tormenta {0} daño/s en radio 223 (encadena 1x)",
    "powerup_lightning_aura_desc2": "Tormenta {0} daño/s en radio 289 (encadena 2x)",
    "powerup_lightning_aura_desc3": "Tormenta {0} daño/s en radio 356 (encadena 3x)",
    "powerup_poison_aura_desc1": "Pulso de veneno {0} daño/s en radio 253 (6s, acumulable)",
    "powerup_poison_aura_desc2": "Pulso de veneno {0} daño/s en radio 328 (8s, acumulable)",
    "powerup_poison_aura_desc3": "Pulso de veneno {0} daño/s en radio 404 (10s, acumulable)",
    "powerup_wind_aura_desc1": "Ráfaga cada 3s: empuja enemigos en radio 270",
    "powerup_wind_aura_desc2": "Ráfaga cada 2.6s: empuja enemigos en radio 351",
    "powerup_wind_aura_desc3": "Ráfaga cada 2.2s: empuja enemigos en radio 432",
    "powerup_time_warp_desc": "Ralentiza el tiempo un 50% durante 3.5 s (2 usos/oleada, 10 s de recarga)",
    "powerup_gravity_well_desc": "Atrae a los enemigos en un radio de 300. Otorga un escudo del 10% de vida (5s de retardo antes de regenerar, 5%/s)",
    "powerup_phase_shift_desc": "Dash hacia delante (5 s cd, 0.5 s invuln., escala con velocidad)",
    "powerup_overcharge_desc": "Las balas infligen +10% daño por 100 unidades recorridas (max 150%, alcanza a 1000 unidades)",
    "powerup_echo_shots_desc": "Las balas dejan ecos fantasma (25% de daño)",
    "powerup_rotating_orbs_desc": "Obtienes los 6 orbes elementales ({0})",
    "powerup_poison_orb_desc1": "4 orbes veneno ({0})",
    "powerup_poison_orb_desc2": "8 orbes veneno ({0})",
    "powerup_poison_orb_desc3": "12 orbes veneno ({0})",
    "powerup_fire_orb_desc1": "4 orbes fuego ({0})",
    "powerup_fire_orb_desc2": "8 orbes fuego ({0})",
    "powerup_fire_orb_desc3": "12 orbes fuego ({0})",
    "powerup_lightning_orb_desc1": "4 orbes rayo ({0})",
    "powerup_lightning_orb_desc2": "8 orbes rayo ({0})",
    "powerup_lightning_orb_desc3": "12 orbes rayo ({0})",
    "powerup_wind_orb_desc1": "4 orbes viento que empujan enemigos ({0})",
    "powerup_wind_orb_desc2": "8 orbes viento que empujan enemigos ({0})",
    "powerup_wind_orb_desc3": "12 orbes viento que empujan enemigos ({0})",
    "powerup_frost_orb_desc1": "4 orbes hielo que ralentizan enemigos ({0})",
    "powerup_frost_orb_desc2": "8 orbes hielo que ralentizan enemigos ({0})",
    "powerup_frost_orb_desc3": "12 orbes hielo que ralentizan enemigos ({0})",
    "powerup_arcane_orb_desc1": "4 orbes arcanos ({0})",
    "powerup_arcane_orb_desc2": "8 orbes arcanos ({0})",
    "powerup_arcane_orb_desc3": "12 orbes arcanos ({0})",
    "powerup_arcane_bullets_desc1": "Balas arcanas mejoradas (+20% daño de bala, arcano)",
    "powerup_arcane_bullets_desc2": "Balas arcanas mejoradas (+40% daño de bala, arcano)",
    "powerup_arcane_bullets_desc3": "Balas arcanas mejoradas (+60% daño de bala, arcano)",
    "powerup_arcane_aura_desc1": "Pulso arcano {0} daño/s en radio 200, arcano",
    "powerup_arcane_aura_desc2": "Pulso arcano {0} daño/s en radio 260, arcano",
    "powerup_arcane_aura_desc3": "Pulso arcano {0} daño/s en radio 320, arcano",
    "powerup_fire_mastery_desc": "Fuego: +150% daño, +50% duración y +45% ralentización",
    "powerup_poison_mastery_desc": "Veneno: +150% daño, +200% duración y +40% ralentización",
    "powerup_frost_mastery_desc": "Escarcha: +25% ralentización (hasta 85%) y orbes que enfrían 55%",
    "powerup_arcane_mastery_desc": "Arcano: +75% daño y las balas perforan",
    "powerup_lightning_mastery_desc": "Rayo: +150% daño, +25% ralentización, +1 cadena y +50% de alcance",
    "powerup_wind_mastery_desc": "Viento: +150% daño, +45% ralentización y empuje x3.5",
    "powerup_parry_desc": "Activo: invulnerable 0.5 s y rebota balas enemigas (5 s de recarga)",
    "powerup_blood_orb_desc1": "4 orbes sangre ({0}, 1.75% robo vida)",
    "powerup_blood_orb_desc2": "8 orbes sangre ({0}, 2.25% robo vida)",
    "powerup_blood_orb_desc3": "12 orbes sangre ({0}, 3% robo vida)",
    "powerup_blood_aura_desc1": "Pulso de sangre: {0} daño/s en radio 210 y cura un 2.5% del daño infligido",
    "powerup_blood_aura_desc2": "Pulso de sangre: {0} daño/s en radio 273 y cura un 5% del daño infligido",
    "powerup_blood_aura_desc3": "Pulso de sangre: {0} daño/s en radio 336 y cura un 7.5% del daño infligido",
    "powerup_blood_mastery_desc": "Sangre: +100% daño y +100% robo de vida",
    "powerup_radial_burst_desc1": "Dispara 8 balas en círculo cada 3.5 s (usa tu daño)",
    "powerup_radial_burst_desc2": "Dispara 10 balas en círculo cada 3.0 s (usa tu daño)",
    "powerup_radial_burst_desc3": "Dispara 14 balas en círculo cada 2.0 s (usa tu daño)",
    "powerup_wall_turrets_desc1": "Los muros disparan (100 + {0} [30%] daño, 1.5 s recarga, 350px rango)",
    "powerup_wall_turrets_desc2": "Los muros disparan más rápido (100 + {0} [30%] daño, 1.0 s recarga, 425px rango)",
    "powerup_wall_turrets_desc3": "Los muros disparan doble (100 + {0} [30%] daño x2, 1.0 s recarga, 500px rango)",
    "powerup_pulse_armor_desc1": "Al recibir daño, empuja enemigos cercanos (sin daño, +1% maxHP escalado)",
    "powerup_pulse_armor_desc2": "Onda empuja más lejos e inflige 200 + 1% maxHP daño",
    "powerup_pulse_armor_desc3": "Onda empuja aún más lejos e inflige 400 + 1% maxHP daño",
    "powerup_heavy_rounds_desc1": "Balas 15% más grandes con ligero retroceso",
    "powerup_heavy_rounds_desc2": "Balas 25% más grandes con retroceso aumentado",
    "powerup_heavy_rounds_desc3": "Balas 35% más grandes con fuerte retroceso",
    "powerup_fortified_desc1": "Reduce el daño recibido un 10% y te da 250 HP máximos",
    "powerup_fortified_desc2": "Reduce el daño recibido un 20% y te da 500 (+250) HP máximos",
    "powerup_fortified_desc3": "Reduce el daño recibido un 30% y te da 750 (+250) HP máximos",
    "powerup_special_rounds_desc1": "Cada 4ª bala causa +75% de daño extra",
    "powerup_special_rounds_desc2": "Cada 3ª bala causa +75% de daño extra",
    "powerup_special_rounds_desc3": "Cada 2ª bala causa +75% de daño extra",
    "powerup_giant_slayer_desc1": "Inflige daño extra igual al 2.5% del HP actual del enemigo (0.5% vs jefes)",
    "powerup_giant_slayer_desc2": "Inflige daño extra igual al 4% del HP actual del enemigo (0.8% vs jefes)",
    "powerup_giant_slayer_desc3": "Inflige daño extra igual al 6% del HP actual del enemigo (1.2% vs jefes)",
    "powerup_curse_desc1": "Maldice al 25% de los enemigos, inflige +30% de daño a los malditos (muy reducido contra jefes)",
    "powerup_curse_desc2": "Maldice al 35% de los enemigos, inflige +45% de daño a los malditos (muy reducido contra jefes)",
    "powerup_curse_desc3": "Maldice al 50% de los enemigos, inflige +60% de daño a los malditos (muy reducido contra jefes)",
    "powerup_celestial_veil_desc": "Anula 2 golpes por oleada, se reinicia al empezar cada oleada",
    "powerup_volatile": "Volátil",
    "powerup_volatile_desc": "Enemigos con 2+ efectos elementales reciben +50% daño de bala, al morir, propagan sus elementos cerca",
    "powerup_resonance": "Resonancia",
    "powerup_resonance_desc1": "Tus balas infligen daño extra igual al 20% del DPS elemental combinado si el objetivo tiene DoTs",
    "powerup_resonance_desc2": "Tus balas infligen daño extra igual al 30% del DPS elemental combinado si el objetivo tiene DoTs",
    "powerup_resonance_desc3": "Tus balas infligen daño extra igual al 40% del DPS elemental combinado si el objetivo tiene DoTs",
    "powerup_blood_pact": "Pacto de Sangre",
    "powerup_blood_pact_desc": "Sacrifica el 20% de tu HP actual para desatar una nova de sangre que golpea a CADA enemigo por el 25% de su HP máximo + 2.5 daño por HP sacrificado. Los jefes la resisten en un 60%. Recarga 3 s",
    "powerup_conduit": "Conducto",
    "powerup_conduit_desc": "Detona todos los DoTs activos por 3x su daño restante y luego los elimina. Recarga 15 s",
    "powerup_aftershock": "Réplica",
    "powerup_aftershock_desc": "Emite una onda con tus últimos 2 s de movimiento, daña y empuja. Recarga 14 s",
    "powerup_nova": "Nova",
    "powerup_nova_desc": "Congela tus balas 2 s y luego las libera juntas a 1.5x velocidad. Recarga 16 s",
    "powerup_heal_power": "Oleada Vital",
    "powerup_heal_power_desc1": "Toda la curación recibida se amplifica un 15 %. Afecta a regeneración, roba-vida y consumibles.",
    "powerup_heal_power_desc2": "Toda la curación recibida se amplifica un 20 %. Afecta a regeneración, roba-vida y consumibles.",
    "powerup_heal_power_desc3": "Toda la curación recibida se amplifica un 25 %. Afecta a regeneración, roba-vida y consumibles.",
    "powerup_bountiful": "Cornucopia",
    "powerup_bountiful_desc": "Doble drop de consumibles. Son un 50% más potentes y duran un 50% más. Cada 15 kills activa un jackpot.",

    # Stats Window
    "stats_window_title": "Monitor del Sistema - Análisis de Jugador",
    "stats_tab_lifetime": "Permanente",
    "stats_tab_last_run": "Última Ejecución",
    "stats_tab_power_ups": "Mejoras",
    "stats_performance_monitor": "=== MONITOR DE RENDIMIENTO DEL SISTEMA ===",
    "stats_total_sessions": "SESIONES TOTALES",
    "stats_playtime": "TIEMPO DE JUEGO",
    "stats_peak_kills": "MÁXIMO DE MUERTES",
    "stats_wave_mode_metrics": "MÉTRICAS DEL MODO OLEADA",
    "stats_time_survival_metrics": "MÉTRICAS DE SUPERVIVENCIA",
    "stats_combat": "COMBATE",
    "stats_accuracy": "Precisión",
    "stats_shots_fired": "Disparos Realizados",
    "stats_shots_hit": "Disparos Impactados",
    "stats_damage_dealt": "Daño Infligido",
    "stats_damage_taken": "Daño Recibido",
    "stats_elite_kills": "Muertes de Élite",
    "stats_boss_kills": "Muertes de Jefe",
    "stats_critical_hits": "Golpes Críticos",
    "stats_movement_survival": "MOVIMIENTO Y SUPERVIVENCIA",
    "stats_distance": "Distancia",
    "stats_phase_shifts": "Cambios de Fase",
    "stats_time_warps": "Distorsiones Temporales",
    "stats_near_deaths": "Casi Muertes",
    "stats_best_streak": "Mejor Racha",
    "stats_no_hit_streak": "Racha Sin Daño",
    "stats_time_at_low_hp": "Tiempo a HP Bajo",
    "stats_successful_parries": "Paradas Exitosas",
    "stats_time_invincible": "Tiempo Invencible",
    "stats_performance": "RENDIMIENTO",
    "stats_peak_dps": "DPS Máximo",
    "stats_average_dps": "DPS Promedio",
    "stats_kills_per_min": "Muertes/Min",
    "stats_avg_wave": "Oleada Prom",
    "stats_fastest_wave": "Oleada Más Rápida",
    "stats_resources": "RECURSOS",
    "stats_coins_earned": "Monedas Ganadas",
    "stats_coins_spent": "Monedas Gastadas",
    "stats_coins_saved": "Monedas Ahorradas",
    "stats_walls_placed": "Muros Colocados",
    "stats_consumables": "Consumibles",
    "stats_shop_purchases": "Compras en Tienda",
    "stats_play_style": "ESTILO DE JUEGO",
    "stats_aggression": "Agresión",
    "stats_caution": "Precaución",
    "stats_dps_over_time": "DPS A TRAVÉS DEL TIEMPO",
    "stats_no_graph_data": "Sin datos de gráfico",
    "stats_max_combo": "Combo Máximo",
    "stats_avg_combo": "Combo Promedio",
    "stats_perfect_waves": "Oleadas Perfectas",
    "stats_wave_mode": "MODO OLEADAS",
    "stats_time_survival_mode": "SUPERVIVENCIA",
    "stats_sandbox_mode": "SANDBOX",
    "stats_pvp_mode": "MODO PVP",
    "stats_combat_label": "COMBATE",
    "stats_accuracy_label": "Precisión",
    "stats_shots_fired_label": "Disparos Realizados",
    "stats_shots_hit_label": "Disparos Impactados",
    "stats_no_previous_run": "No hay estadísticas de ejecución anterior disponibles",
    "stats_complete_game_stats": "¡Completa un juego para ver estadísticas detalladas!",
    "stats_power_up_breakdown": "DESGLOSE DE MEJORAS",
    "stats_timeline": "LÍNEA DE TIEMPO",
    "stats_effectiveness_ranking": "CLASIFICACIÓN DE EFECTIVIDAD",
    "stats_rank": "RANGO",
    "stats_power_up": "MEJORA",
    "stats_damage": "DAÑO",
    "stats_no_damage_data": "Sin datos de daño disponibles",
    "stats_no_power_up_data": "Sin datos de mejora disponibles",

    # Game Over Screen
    "game_over_title": "TODAS LAS AMENAZAS NEUTRALIZADAS",
    "game_over_secure": "ESTADO DEL SISTEMA: [*] SEGURO",
    "game_over_performance_report": "=== INFORME DE RENDIMIENTO ===",
    "game_over_waves_survived": "Oleadas Sobrevividas:",
    "game_over_threats_eliminated": "Amenazas Eliminadas:",
    "game_over_resources_collected": "Recursos Recopilados:",
    "game_over_mission_duration": "Duración de la Misión:",
    "game_over_continue": "CONTINUAR (OLEADA",
    "game_over_save_log": "[G] GUARDAR REGISTRO",
    "game_over_critical_failure": "FALLO CRÍTICO DEL SISTEMA",
    "game_over_error_msg": "Tu sistema ha encontrado un error crítico y necesita reiniciarse.",
    "game_over_session_diagnostics": "=== DIAGNÓSTICO DE SESIÓN ===",
    "game_over_wave_reached": "Oleada Alcanzada:",
    "game_over_system_uptime": "Tiempo de Actividad del Sistema:",
    "game_over_restart_system": "REINICIAR SISTEMA",
    "game_over_view_logs": "VER REGISTROS",
    "game_over_exit": "SALIR",
    "game_over_error_code": "CÓDIGO DE ERROR: INTEGRIDAD_AGOTADA_0x00000000",
    "game_over_security_level_max": "NIVEL DE SEGURIDAD: MÁXIMO | TODOS LOS PROCESOS ESTABLES",
    "game_over_system_failed_footer": "[!] El sistema permanecerá en estado fallido hasta reinicio manual",
    "game_over_system_secure_footer": "[OK] Todos los sistemas operacionales | Cuadrícula defensiva en máxima eficiencia",

    # Victory Screen (oleada 60, jefe final superado)
    "victory_title": "MISIÓN COMPLETADA",
    "victory_subtitle": "¡Purgaste la intrusión final y superaste las 60 oleadas!",
    "victory_status": "SISTEMA TOTALMENTE SEGURO -- NIVEL DE AMENAZA CERO",
    "victory_report_header": "=== DIAGNÓSTICO FINAL ===",
    "victory_bosses_defeated": "Jefes Derrotados:",
    "victory_continue_endless": "MODO INFINITO",
    "victory_view_stats": "VER ESTADÍSTICAS",
    "victory_return_menu": "VOLVER AL MENÚ",
    "victory_footer": "[OK] Protocolo infinito desbloqueado | ¿Cuánto resistirás?",

    # Game Over "cause of death" lines
    "game_over_cause_label": "CAUSA DE LA TERMINACIÓN",
    "death_contact": "Aplastado por",
    "death_boss_contact": "Aniquilado por",
    "death_projectile": "Abatido por",
    "death_laser": "Desintegrado por",
    "death_explosion": "Alcanzado por la explosión de",
    "death_meteorite": "Bombardeado por",
    "death_poison": "Corroído por",
    "death_hazard": "Perdido ante un peligro de la arena",
    "death_unknown": "Conexión con el host terminada",
    "death_boss_tag": "JEFE",

    # HUD/Notifications
    "hud_system_status": "ESTADO DEL SISTEMA",
    "hud_integrity": "INTEGRIDAD:",
    "hud_charges": "CARGAS",
    "hud_processes": "PROCESOS",
    "hud_cache": "CACHÉ",
    "hud_performance": "Rendimiento",
    "hud_wave": "OLEADA:",
    "hud_uptime": "TIEMPO DE ACTIVIDAD:",
    "hud_threats": "AMENAZAS:",
    "notif_wave_initiated": "Oleada iniciada",
    "notif_wave_cleared": "Oleada despejada",

    # Debug Panel
    "debug_panel_diagnostics": "DIAGNÓSTICOS",
    "debug_panel_fps": "FPS",
    "debug_panel_entities": "Ent",
    "debug_panel_active_effects": "Efectos Activos",
    "debug_panel_combat_stats": "Estadísticas de Combate",
    "debug_panel_damage": "Daño",
    "debug_panel_fire_rate": "Cadencia",
    "debug_panel_speed": "Velocidad",
    "debug_panel_low_hp_bonuses": "Bonificaciones Bajo HP",
    "debug_panel_rage": "Furia",
    "debug_panel_berserker": "Berserker",
    "debug_panel_effect_speed": "Velocidad",
    "debug_panel_effect_invuln": "Invuln",
    "debug_panel_effect_fire": "Fuego",
    "debug_panel_effect_magnet": "Imán",
    "debug_panel_effect_time_warp": "Deformación Temporal",
    "debug_panel_effect_phase": "Fase",
    "debug_panel_effect_parry": "Parada",
    "debug_panel_active": "ACTIVO",
    "debug_panel_run_stats": "Estadísticas de Ejecución:",
    "debug_panel_wave_label": "Oleada",
    "debug_panel_time_label": "Tiempo",

    # Shop tabs
    "shop_tab_player": "JUGADOR",
    "shop_tab_bullet": "BALA",
    "shop_tab_bshapes": "F.BALA",
    "shop_tab_shapes": "FORMAS",
    "shop_tab_particles": "PARTÍCULAS",
    "shop_tab_desktop": "ESCRITORIO",
    "shop_tab_cubeskins": "CUBOS",
    "shop_scroll_hint": "Rueda del ratón para ver más",
    "shop_click_equip": "Clic para equipar",
    "shop_window_title": "Tienda Personaliz.",
    "shop_equipped": "[EQUIPADO]",
    "shop_currently_equipped": "Equipado:",
    "shop_customize_appearance": "PERSONALIZA TU APARIENCIA",
    "shop_customize_bullets": "PERSONALIZA TUS BALAS",
    "shop_choose_shape": "ELIGE TU FORMA",
    "shop_customize_effects": "PERSONALIZA EFECTOS",
    "shop_customize_desktop": "PERSONALIZA EL FONDO DE ESCRITORIO",
    "shop_customize_cubeskins": "PERSONALIZA LOS ASPECTOS DE CUBOS",

    # Secret items (pestaña SECRETO de la tienda)
    "shop_tab_secret": "SECRETO",
    "shop_customize_secret": "OBJETOS SECRETOS",
    "secret_tophat_name": "Sombrero del Kernel",
    "secret_tophat_desc": "El sombrero de copa del propio kernel, confiado a quien aseguró el sistema.",
    "secret_tophat_unequipped": "[DESEQUIPADO]",
    "secret_click_to_wear": "Clic para llevarlo",
    "secret_locked_hint": "Derrota al jefe final de la oleada 60 para desbloquearlo",
    "secret_unknown_locked_hint": "Condicion de desbloqueo desconocida",
    "secret_orbital_cube_name": "Cubo Orbital",
    "secret_orbital_cube_desc": "Expulsado de su órbita, el cubo del escritorio encontró una nueva: tú.",
    "secret_cube_locked_hint": "Consigue el logro 'Escape Velocity' para desbloquearlo",
    "secret_cheater_hat_name": "Sombrero de Tramposo",
    "secret_cheater_hat_desc": "Un sombrero muy blanco y puntiagudo para quienes saben exactamente qué hace cd+.",
    "victory_secret_unlocked": "[NUEVO] SECRETO DESBLOQUEADO: SOMBRERO DEL KERNEL -- ¡equipado! Actívalo en la pestaña SECRETO de la tienda.",

    # Desktop Background Skins
    "dbg_default": "Cuadrícula OS",
    "dbg_default_desc": "Placa de circuito animada clásica",
    "dbg_neon": "Ciudad Neón",
    "dbg_neon_desc": "Luces de neón rosas y moradas",
    "dbg_matrix": "Lluvia de Datos",
    "dbg_matrix_desc": "Cascadas de código verde",
    "dbg_void": "Vacío Profundo",
    "dbg_void_desc": "Espacio oscuro con estrellas lejanas",
    "dbg_sunrise": "Amanecer del Sistema",
    "dbg_sunrise_desc": "Cálido resplandor naranja del horizonte",
    "dbg_ocean": "Red Neuronal",
    "dbg_ocean_desc": "Nodos azules interconectados",
    "dbg_inferno": "Núcleo Infernal",
    "dbg_inferno_desc": "Ondas de calor volcánico rojas",
    "dbg_portal": "Prueba Aperture",
    "dbg_portal_desc": "Portales gemelos intercambian luz en la cámara",
    "dbg_horror": "Pánico del Kernel",
    "dbg_horror_desc": "Pavor en la oscuridad - hasta el cubo tiembla de miedo",
    "dbg_cyber": "Ciberespacio",
    "dbg_cyber_desc": "Circuitos vivos, pulsos de datos y paneles HUD con fallos",
    "dbg_casino": "Gran Apostador",
    "dbg_casino_desc": "Fieltro verde, palos de la suerte, fichas y oro",
    "dbg_dragon": "Guarida del Dragón",
    "dbg_dragon_desc": "Dragones negros enroscados en los bordes de una oscuridad rúnica",

    # Cube Skins
    "csk_default": "Unidad del Sistema",
    "csk_default_desc": "Cubo de combate clásico",
    "csk_neon": "Pulso Neón",
    "csk_neon_desc": "Energía morada neón brillante",
    "csk_ice": "Núcleo Criogénico",
    "csk_ice_desc": "Caparazón cristalino azul hielo",
    "csk_gold": "Estándar de Oro",
    "csk_gold_desc": "Lujoso revestimiento dorado",
    "csk_shadow": "Nodo Sombra",
    "csk_shadow_desc": "Chasis oscuro en modo sigilo",
    "csk_plasma": "Equipo de Plasma",
    "csk_plasma_desc": "Plasma eléctrico azul-morado",
    "csk_matrix": "Nodo de Datos",
    "csk_matrix_desc": "Flujos de datos verde matrix",
    "csk_companion": "Cubo de Compañía",
    "csk_companion_desc": "Nunca amenazará con apuñalarte. El corazón es puramente decorativo.",
    "csk_jack": "Nodo Calabaza",
    "csk_jack_desc": "Una calabaza tallada e iluminada por dentro. Demasiado engreída para temer a la oscuridad.",
    "csk_cyber": "Ciberdeck",
    "csk_cyber_desc": "Paneles HUD holográficos brillan en cada cara.",
    "csk_dice": "Dado de la Suerte",
    "csk_dice_desc": "Tira el dado. Puntos en cada cara.",
    "csk_d20": "Colmillo de Dragón",
    "csk_d20_desc": "Un dado de veinte caras de verdad, obsidiana y oro. Tira por la guarida.",

    # Player Skins
    "skin_default": "Sistema base",
    "skin_default_desc": "Interfaz clásica del sistema",
    "skin_neon_pink": "Rosa Neón",
    "skin_neon_pink_desc": "Estilo ciberpunk magenta",
    "skin_emerald": "Esmeralda",
    "skin_emerald_desc": "Tecnología verde avanzada",
    "skin_sunset": "Atardecer",
    "skin_sunset_desc": "Naranja y rojo incandescentes",
    "skin_amethyst": "Amatista",
    "skin_amethyst_desc": "Energía púrpura",
    "skin_gold": "Dorado",
    "skin_gold_desc": "Brillo dorado lujoso",
    "skin_ice": "Cristal",
    "skin_ice_desc": "Belleza cristalina helada",
    "skin_shadow": "Sombra",
    "skin_shadow_desc": "Sigilo en modo oscuro",
    "skin_rainbow": "Arcoíris",
    "skin_rainbow_desc": "Espectro arcoíris animado",
    "skin_matrix": "Matrix",
    "skin_matrix_desc": "Cascada de datos verdes",
    "skin_void": "Vacío",
    "skin_void_desc": "Energía púrpura del vacío",
    "skin_plasma": "Plasma",
    "skin_plasma_desc": "Plasma azul violáceo",
    "skin_stars": "Lluvia Estelar",
    "skin_stars_desc": "Destello blanco dorado",
    "skin_lightning": "Tormenta",
    "skin_lightning_desc": "Azul eléctrico crepitante",

    # Bullet Skins
    "bullet_default": "Sistema base",
    "bullet_default_desc": "Proyectil clásico cian",
    "bullet_neon_pink": "Rosa Neón",
    "bullet_neon_pink_desc": "Proyectiles magenta neón",
    "bullet_emerald": "Esmeralda",
    "bullet_emerald_desc": "Energía verde avanzada",
    "bullet_sunset": "Atardecer",
    "bullet_sunset_desc": "Proyectiles naranja ardiente",
    "bullet_amethyst": "Amatista",
    "bullet_amethyst_desc": "Energía púrpura",
    "bullet_gold": "Dorado",
    "bullet_gold_desc": "Disparos de brillo dorado",
    "bullet_ice": "Cristal",
    "bullet_ice_desc": "Disparos cristalinos",
    "bullet_shadow": "Sombra",
    "bullet_shadow_desc": "Proyectiles oscuros sigilosos",
    "bullet_rainbow": "Arcoíris",
    "bullet_rainbow_desc": "Espectro arcoíris animado",
    "bullet_matrix": "Matrix",
    "bullet_matrix_desc": "Cascada de datos verdes",
    "bullet_void": "Vacío",
    "bullet_void_desc": "Energía púrpura del vacío",
    "bullet_plasma": "Plasma",
    "bullet_plasma_desc": "Plasma azul violáceo",
    "bullet_stars": "Lluvia Estelar",
    "bullet_stars_desc": "Disparos blanco dorados",
    "bullet_lightning": "Tormenta",
    "bullet_lightning_desc": "Rayos eléctricos crepitantes",

    # Shapes
    "shape_hexagon": "Hexágono",
    "shape_hexagon_desc": "Forma hexagonal clásica",
    "shape_triangle": "Triángulo",
    "shape_triangle_desc": "Forma triangular afilada",
    "shape_square": "Cuadrado",
    "shape_square_desc": "Forma cuadrada sólida",
    "shape_circle": "Círculo",
    "shape_circle_desc": "Forma circular pura",

    # Bullet Shapes
    "bshape_circle": "Clásico",
    "bshape_circle_desc": "Bala circular estándar",
    "bshape_triangle": "Fragmento",
    "bshape_triangle_desc": "Disparo triangular",
    "bshape_diamond": "Cristal",
    "bshape_diamond_desc": "Proyectil diamante",
    "bshape_square": "Bloque",
    "bshape_square_desc": "Bala cuadrada sólida",
    "bshape_star": "Estrella",
    "bshape_star_desc": "Ráfaga de seis puntas",
    "bshape_pentagon": "Pentágono",
    "bshape_pentagon_desc": "Proyectil de cinco lados",
    "shop_customize_bshapes": "FORMA DE LAS BALAS",
    "particle_default": "Sistema base",
    "particle_default_desc": "Energía cian estándar",
    "particle_fire": "Llamas",
    "particle_fire_desc": "Partículas de llama",
    "particle_ice": "Escarcha",
    "particle_ice_desc": "Fragmentos helados",
    "particle_toxic": "Tóxico",
    "particle_toxic_desc": "Nube tóxica verdosa",
    "particle_plasma": "Plasma",
    "particle_plasma_desc": "Energía violácea eléctrica",
    "particle_gold": "Dorado",
    "particle_gold_desc": "Polvo dorado",
    "particle_shadow": "Humo",
    "particle_shadow_desc": "Estelas oscuras",
    "particle_rainbow": "Arcoíris",
    "particle_rainbow_desc": "Confeti colorido",
    "particle_stars": "Estrellas",
    "particle_stars_desc": "Partículas de estrellas titilantes",
    "particle_hearts": "Corazones",
    "particle_hearts_desc": "Partículas de corazones",
    "particle_lightning": "Relámpago",
    "particle_lightning_desc": "Chispas eléctricas amarillas",
    "particle_void": "Vacío",
    "particle_void_desc": "Grietas oscuras dimensionales",
    "particle_amethyst": "Flor de Cristal",
    "particle_amethyst_desc": "Brillo de cristal violeta",
    "particle_matrix": "Lluvia de Código",
    "particle_matrix_desc": "Datos verdes en cascada",

    # Cosmetic Packs (paquetes tematicos con descuento)
    "shop_tab_packs": "PAQUETES",
    "shop_customize_packs": "Paquetes Tematicos -- 40% Off",
    "pack_owned": "OBTENIDO",
    "pack_buy": "COMPRAR PAQUETE",
    "pack_includes": "Jugador + Bala + Particula",
    "pack_gold": "Paquete Dorado",
    "pack_gold_desc": "Todos los cosmeticos Dorados",
    "pack_ice": "Paquete Cristal",
    "pack_ice_desc": "Todos los cosmeticos Cristal",
    "pack_shadow": "Paquete Sombra",
    "pack_shadow_desc": "Todos los cosmeticos Sombra",
    "pack_rainbow": "Paquete Arcoiris",
    "pack_rainbow_desc": "Todos los cosmeticos Arcoiris",
    "pack_void": "Paquete Vacio",
    "pack_void_desc": "Todos los cosmeticos Vacio",
    "pack_plasma": "Paquete Plasma",
    "pack_plasma_desc": "Todos los cosmeticos Plasma",
    "pack_sunset": "Paquete Atardecer",
    "pack_sunset_desc": "Atardecer con estela de fuego",
    "pack_emerald": "Paquete Esmeralda",
    "pack_emerald_desc": "Esmeralda con estela toxica",
    "pack_neon_pink": "Paquete Rosa Neon",
    "pack_neon_pink_desc": "Rosa Neon con corazones",
    "pack_amethyst": "Paquete Amatista",
    "pack_amethyst_desc": "Todos los cosmeticos Amatista",
    "pack_matrix": "Paquete Matrix",
    "pack_matrix_desc": "Todos los cosmeticos Matrix",
    "pack_stars": "Paquete Estelar",
    "pack_stars_desc": "Todos los cosmeticos Estelares",
    "pack_lightning": "Paquete Tormenta",
    "pack_lightning_desc": "Todos los cosmeticos Tormenta",

    # Legendary Panel
    "legendary_panel_title": "LEGENDARIO",
    "legendary_chronos": "Cronos",
    "legendary_phase": "Fase",
    "legendary_parry": "Parada",
    "legendary_active": "ACTIVO",
    "legendary_ready": "Listo",
    "legendary_dashing": "SALTANDO",
    "legendary_volatile": "Volátil",
    "legendary_resonance": "Resonancia",
    "legendary_blood_pact": "Pacto de Sangre",
    "legendary_conduit": "Conducto",
    "legendary_nova": "Nova",
    "legendary_passive": "PASIVO",
    "legendary_frozen": "CONGELADO",

    "notif_boss_detected": "PROCESO DE JEFE DETECTADO",
    "notif_boss_terminated": "Proceso de jefe terminado",
    "notif_installed": "Instalado:",
    "notif_integrity_compromised": "Integridad comprometida: -",
    "notif_integrity_restored": "Integridad del sistema restaurada: +",
    "notif_resource_acquired": "Recurso adquirido: +",
    "notif_execute": "> EJECUTAR:",
    "notif_cooldown": "enfriamiento:",
    "notif_process_terminated": "Proceso terminado:",
    "notif_processes_terminated": "Procesos terminados:",

    # Help System
    "help_window_title": "Sistema de Ayuda - Terminal",
    "help_available_commands": "  COMANDOS DISPONIBLES",
    "help_controls_keybindings": "CONTROLES Y ATAJOS DE TECLADO",
    "help_gameplay_topic": "MODOS DE JUEGO",
    "help_power_ups_topic": "REFERENCIA DE MEJORAS",
    "help_powerup_locked_name": "??? - No Descubierto",
    "help_powerup_locked_desc": "[BLOQUEADO] Descubre esta mejora durante una partida para revelar sus detalles.",
    "help_enemies_topic": "TIPOS DE ENEMIGOS",
    "help_bosses_topic": "INFORMACIÓN DE JEFES",
    "help_shop_topic": "ARTÍCULOS DE TIENDA",
    "help_clear_command": "Limpiar la pantalla",
    "help_command_separator": "--------------------------------------",
    "help_launch_topics": "jugar/supervivencia/sandbox/estadísticas/ajustes/salir",
    "help_launching_icon": "Lanzando $1...",
    "help_opening_icon": "Abriendo $1...",
    "help_executing_icon": "Ejecutando $1...",
    "help_unknown_command": "Comando desconocido:",
    "help_type_help": "Escriba 'help' para ver comandos disponibles",
    "help_error_executing": "Error ejecutando comando:",

    # Help System - Command descriptions
    "help_cmd_help": "Mostrar esta lista de comandos",
    "help_cmd_controls": "Ver controles y atajos de teclado",
    "help_cmd_gameplay": "Modos de juego y mecánicas",
    "help_cmd_powerups": "Referencia completa de mejoras",
    "help_cmd_enemies": "Tipos de enemigos y comportamientos",
    "help_cmd_bosses": "Información de jefes",
    "help_cmd_shop": "Artículos de tienda y costos",
    "help_cmd_launch_icons": "Lanzar iconos de escritorio por nombre",

    # Help System - Controls section
    "help_movement": "MOVIMIENTO",
    "help_combat": "COMBATE",
    "help_abilities": "HABILIDADES",
    "help_menu": "MENÚ",
    "help_movement_desc": "Mover jugador",
    "help_wasd": "W/A/S/D ............ Mover jugador",
    "help_arrow_keys": "Flechas ............ Movimiento alternativo",
    "help_left_mouse": "Ratón Izq ......... Disparar",
    "help_space": "Espacio ............ Disparar (alternativo)",
    "help_q": "Q .................. Activar Poderes Legendarios",
    "help_e": "E .................. Colocar Muro",
    "help_esc": "ESC ................ Pausa / Volver al menú",
    "help_f11": "F11 ................ Alternar Pantalla Completa",

    # Help System - Gameplay section
    "help_wave_mode": "MODO OLEADAS",
    "help_wave_mode_desc": "- Elimina oleadas de enemigos\n  - Jefe aparece cada 5ta oleada\n  - Elige mejora después de cada oleada\n  - Tienda abre después de seleccionar mejora",
    "help_survival_mode": "MODO SUPERVIVENCIA",
    "help_survival_mode_desc": "- Sobrevive hordas infinitas de enemigos\n  - Los enemigos aparecen continuamente\n  - Jefe aparece cada 60 segundos",
    "help_sandbox_mode": "MODO SANDBOX",
    "help_sandbox_mode_desc": "- Modo de prueba con controles de aparición\n  - Experimenta con diferentes escenarios",

    # Help System - Power-ups section
    "help_common_powerups": "MEJORAS COMUNES",
    "help_elemental_orbs": "ORBES ELEMENTALES",
    "help_elemental_auras": "AURAS ELEMENTALES",
    "help_legendary_powerups": "MEJORAS LEGENDARIAS (Presiona Q)",

    # Help System - Enemy section
    "help_enemy_circle": "CÍRCULO (Perseguidor)",
    "help_enemy_cube": "CUBO (Torreta)",
    "help_enemy_triangle": "TRIÁNGULO (Agilista)",
    "help_enemy_star": "ESTRELLA (Tanque)",
    "help_enemy_hexagon": "HEXÁGONO (Teletransportador)",
    "help_enemy_elite": "VARIANTES ÉLITE",

    # Help System - Boss section
    "help_boss_spawning": "APARICIÓN DE JEFES",
    "help_boss_mechanics": "MECÁNICAS DE JEFES",
    "help_boss_attacks": "ATAQUES DE JEFES",
    "help_boss_rewards": "RECOMPENSAS",

    # Help System - Shop section
    "help_available_items": "ARTÍCULOS DISPONIBLES",
    "help_cost_scaling": "ESCALADO DE COSTOS",
    "help_earning_coins": "GANANDO MONEDAS",
    "help_shop_access": "ACCESO A TIENDA",

    # Help System - Powerup names
    "help_double_shot": "Doble Disparo - Dispara 2 balas por tiro",
    "help_rotating_shield": "Escudo Giratorio - Escudo protector orbitante",
    "help_magical_bullets": "Balas Mágicas - Las balas rastrean enemigos",
    "help_piercing_shots": "Disparos Penetrantes - Las balas pasan por enemigos",
    "help_multi_shot": "Disparo Múltiple - Dispara en 3 direcciones",
    "help_explosive_bullets": "Balas Explosivas - Las balas explotan al impacto",
    "help_life_steal": "Robo de Vida - Gana HP al matar",
    "help_rapid_fire": "Fuego Rápido - Tasa de fuego aumentada",
    "help_max_health": "Salud Máxima - Aumenta HP máximo",
    "help_speed_boost": "Aumento de Velocidad - Aumento de velocidad permanente",
    "help_bullet_speed": "Velocidad de Balas - Balas más rápidas",
    "help_lucky_coins": "Monedas Afortunadas - Duplica monedas recolectadas",
    "help_wall_master": "Maestro de Muros - Coloca muros más fuertes",
    "help_regeneration": "Regeneración - Restaura lentamente HP",
    "help_dodge_chance": "Oportunidad de Esquivar - Oportunidad de evadir daño",
    "help_critical_hit": "Golpe Crítico - Daño crítico aleatorio",
    "help_blood_bullets": "Balas de Sangre - Robo de vida al impacto",
    "help_bullet_ricochet": "Rebote de Balas - Las balas rebotan en enemigos",
    "help_slow_field": "Campo de Lentitud - Los enemigos se mueven más lentamente",
    "help_rage": "Furia - El daño aumenta con HP bajo",
    "help_berserker": "Berserker - Velocidad de ataque con HP bajo",
    "help_thorns": "Espinas - Refleja daño a atacantes",
    "help_bullet_split": "División de Balas - Las balas se dividen al impactar",
    "help_chain_lightning": "Rayo en Cadena - El daño se encadena entre enemigos",
    "help_frost_shots": "Disparos Helados - Las balas ralentizan enemigos",
    "help_poison_shot": "Disparo Venenoso - Balas venenosas con DoT",
    "help_fire_bullets": "Balas de Fuego - Daño de fuego continuo",
    "help_wind_bullets": "Balas de Viento - Las balas empujan enemigos",
    "help_overcharge": "Sobrecarga - Las balas ganan poder con la distancia",
    "help_echo_shots": "Disparos de Eco - Las balas dejan senderos dañinos",
    "help_poison_orb": "Orbe de Veneno - Orbe elemental de veneno",
    "help_fire_orb": "Orbe de Fuego - Orbe elemental de fuego",
    "help_lightning_orb": "Orbe de Rayo - Orbe elemental de rayo",
    "help_wind_orb": "Orbe de Viento - Orbe elemental de viento",
    "help_frost_orb": "Orbe de Escarcha - Orbe elemental de escarcha",
    "help_arcane_orb": "Orbe Arcano - Orbe elemental arcano",
    "help_blood_orb": "Orbe de Sangre - Orbe elemental de sangre",
    "help_fire_aura": "Aura de Fuego - Aura de daño de fuego continuo",
    "help_lightning_aura": "Aura de Rayo - Rayos se encadenan entre enemigos",
    "help_poison_aura": "Aura de Veneno - Aura de daño venenoso continuo",
    "help_wind_aura": "Aura de Viento - Ráfaga periódica que empuja enemigos",
    "help_arcane_aura": "Aura Arcana - Aura de daño arcano mejorada",
    "help_blood_aura": "Aura de Sangre - Aura de daño con robo de vida",
    "help_time_warp": "Deformación de Tiempo - Ralentiza el tiempo globalmente",
    "help_gravity_well": "Pozo de Gravedad - Atrae enemigos hacia ti",
    "help_phase_shift": "Cambio de Fase - Teletransporte de dash a través de enemigos",
    "help_parry": "Parada - Invulnerable + rebota balas",
    "help_rotating_orbs": "Orbes Giratorios - Todos los orbes elementales a la vez",
    "help_fire_mastery": "Dominio del Fuego - Mejora todos los efectos de fuego",
    "help_poison_mastery": "Dominio del Veneno - Mejora todos los efectos de veneno",
    "help_frost_mastery": "Dominio de la Escarcha - Mejora todos los efectos de escarcha",
    "help_arcane_mastery": "Dominio Arcano - Mejora todos los efectos arcanos",
    "help_lightning_mastery": "Dominio del Rayo - Mejora los efectos de rayo",
    "help_wind_mastery": "Dominio del Viento - Mejora todos los efectos de viento",
    "help_blood_mastery": "Dominio de la Sangre - Mejora todos los efectos de sangre",
    "help_arcane_bullets": "Balas Arcanas - Daño de bala con efecto arcano",
    "help_radial_burst": "Ráfaga Radial - Dispara un círculo de balas periódicamente",
    "help_wall_turrets": "Centinelas de Muro - Los muros disparan enemigos cercanos",
    "help_pulse_armor": "Armadura de Pulso - Recibir daño emite una onda",
    "help_heavy_rounds": "Balas Pesadas - Balas más grandes con retroceso",
    "help_fortified": "Fortificado - Reduce daño recibido y sube HP máx",
    "help_special_rounds": "Balas Especiales - La 5.ª bala causa daño extra",
    "help_giant_slayer": "Matador de Gigantes - Daño extra vs enemigos con mucho HP",
    "help_curse": "Maldición - Maldice enemigos al azar para infligirles daño extra",
    "help_celestial_veil": "Velo Celestial - Anula dos golpes por oleada",
    "help_volatile": "Volátil - Enemigos con 2+ DoTs sufren +50% daño",
    "help_resonance": "Resonancia - Balas en objetivos DoT causan bono elemental",
    "help_blood_pact": "Pacto de Sangre - Sacrifica HP para golpear a cada enemigo por parte de su HP máximo",
    "help_conduit": "Conducto - Detona todos los DoTs por 3x daño",
    "help_aftershock": "Réplica - Onda de choque sigue tu camino de movimiento",
    "help_nova": "Nova - Congela balas y las libera al +50% velocidad",
    "help_heal_power": "Poder de Curación - Aumenta toda la curación recibida",
    "help_bountiful": "Cornucopia - Más consumibles y efectos mejorados",

    # Help System - Shop items
    "help_shop_damage_plus": "Daño + (13 CR base)",
    "help_shop_damage_plus_desc": "Mejora de daño de las balas",
    "help_shop_fire_rate_plus": "Cadencia + (13 CR base)",
    "help_shop_fire_rate_plus_desc": "Mejora de cadencia",
    "help_shop_move_speed_plus": "Velocidad + (10 CR base)",
    "help_shop_move_speed_plus_desc": "Mejora de movimiento",
    "help_shop_max_health_plus": "Vida Máx + (14 CR base)",
    "help_shop_max_health_plus_desc": "Aumento de vida máxima",
    "help_shop_bullet_speed_plus": "Vel. Balas + (9 CR base)",
    "help_shop_bullet_speed_plus_desc": "Mejora de velocidad de balas",
    "help_shop_wall_x4": "Muro x10 (18 CR base)",
    "help_shop_wall_x4_desc": "Compra 10 muros desplegables",

    # Help System - Misc
    "help_wave_mode_info": "Modo Oleadas: Cada 5ta oleada (5, 10, 15...)",
    "help_survival_mode_info": "Modo Supervivencia: Cada 60 segundos",
    "help_enemy_chaser": "- Enemigos de persecución normal\n  - Sigue el movimiento del jugador\n  - Tipo de enemigo más común",
    "help_enemy_turret": "- Disparadores estacionarios o lentos\n  - Dispara proyectiles al jugador\n  - Mantén la distancia",
    "help_enemy_dasher": "- Atacantes de dash rápido\n  - Ráfagas rápidas de velocidad\n  - Peligrosos en combate cercano",
    "help_enemy_tank": "- Enemigos con HP alto\n  - Requiere muchos golpes para derrotar\n  - Dashea cuando se acerca",
    "help_enemy_warper": "- Enemigo caótico de teletransportación\n  - Movimiento impredecible\n  - Puede aparecer en cualquier lugar repentinamente",
    "help_enemy_elite_desc": "- Versiones más fuertes de todos los tipos de enemigos\n  - Dejan caer más monedas al ser derrotados\n  - Aparecen en oleadas posteriores",
    "help_boss_every_5th": "Modo Oleadas: Cada 5ta oleada (5, 10, 15...)",
    "help_boss_every_60_sec": "Modo Supervivencia: Cada 60 segundos",
    "help_cost_scaling_formula": "- Los objetos de tienda tienen límites estrictos\n  - Cada compra es más fuerte y cuesta costBase * 1.8^comprado",
    "help_kill_enemies_to_collect": "- Mata enemigos para recopilar monedas",
    "help_elite_drop_more": "- Los enemigos élite dejan caer más monedas",
    "help_boss_drop_large": "- Los jefes dejan caer grandes cantidades",
    "help_opens_after_powerup": "- Se abre después de seleccionar mejora",
    "help_available_between_waves": "- Disponible entre oleadas",

    # Game Notifications and UI
    "game_wave_announcement_main": "*** OLEADA ***",
    "game_instructions_wall": "E: Muro | ESC: Pausa",
    "game_wall_place": "[Soltar E] Colocar Muro",
    "game_wall_place_remaining": "restantes",
    "game_get_ready": "¡PREPÁRATE!",
    "game_boss_wave_prefix": "OLEADA DE JEFE ",
    "game_incoming": "PRÓXIMAMENTE",
    "game_press_enter_to_start": "Presiona ENTER para comenzar",
    "game_no_data": "Sin datos",
    "game_no_graph_data": "Sin datos de gráfico",
    "game_no_previous_run": "No hay estadísticas de ejecución anterior disponibles",
    "game_complete_game_stats": "Completa un juego para ver estadísticas de ejecución detalladas",
    "game_no_power_up_data": "Sin datos de mejoras disponibles",
    "game_wave_label": "Oleada ",
    "game_best_streak": "Mejor Racha",

    # Stats Window
    "stats_time_column_label": "TIEMPO",
    "stats_damage_column_label": "DAÑO",
    "stats_dealed_abbrev": "Daño Infligido",
    "stats_taken_abbrev": "Daño Recibido",
    "stats_level_prefix": "Nv ",
    "stats_total": "Total",
    "stats_legendary_count": "Legendario",
    "stats_common_count": "Común",

    # Sandbox Mode
    "sandbox_spawn_enemies": "Aparecer Enemigos:",
    "sandbox_spawn_10_random": "Aparecer 10 Aleatorios",
    "sandbox_spawn_bosses": "Aparecer Jefes:",
    "sandbox_god_mode": "Modo Dios:",
    "sandbox_freeze_enemies": "Congelar Enemigos:",
    "sandbox_clear_all_enemies": "Limpiar Todos los Enemigos",
    "sandbox_wave": "Oleada:",
    "sandbox_difficulty": "Dificultad:",
    "sandbox_hp": "HP:",
    "sandbox_enemies": "Enemigos:",
    "sandbox_heal_full": "Curar al Máximo",
    "sandbox_add_coins": "Agregar 1000 Monedas",
    "sandbox_open_shop": "Abrir Tienda",
    "sandbox_roll_power_ups": "Tirar Mejoras",
    "sandbox_title": "MODO SANDBOX",
    "sandbox_tab_enemies": "Enemigos",
    "sandbox_tab_bosses": "Jefes",
    "sandbox_tab_controls": "Controles",
    "sandbox_coins": "Monedas:",
    "sandbox_wave_minus": "Oleada -",
    "sandbox_wave_plus": "Oleada +",
    "sandbox_diff_minus": "Dif -",
    "sandbox_diff_plus": "Dif +",
    "sandbox_toggle": ">>",
    "sandbox_close": "X",
    "sandbox_setup_title": "CONFIGURAR SANDBOX",
    "sandbox_setup_subtitle": "Ajusta tu equipamiento, elige un preajuste o usa el promedio de cualquier oleada.",
    "sandbox_stat_max_hp": "Vida Máx.",
    "sandbox_stat_damage": "Daño",
    "sandbox_stat_fire_rate": "Cadencia",
    "sandbox_stat_move_speed": "Velocidad",
    "sandbox_stat_bullet_speed": "Vel. Proyectil",
    "sandbox_stat_walls": "Muros",
    "sandbox_stat_coins": "Monedas",
    "sandbox_stat_start_wave": "Oleada Inicial",
    "sandbox_presets": "PREAJUSTES",
    "sandbox_preset_fresh": "Inicio Nuevo",
    "sandbox_preset_early": "Inicio (O5)",
    "sandbox_preset_mid": "Medio (O15)",
    "sandbox_preset_late": "Avanzado (O30)",
    "sandbox_preset_end": "Final (O60)",
    "sandbox_preset_glass": "Cañón de Cristal",
    "sandbox_preset_tank": "Coloso",
    "sandbox_apply_wave_avg": "Usar Promedio",
    "sandbox_start_run": "Iniciar Sandbox",
    "sandbox_back": "Volver",
    "sandbox_custom_loadout": "Equipamiento personalizado",

    # Cheat Menu
    "cheat_menu_title": "MENÚ DE TRUCOS (COMPILACIÓN DE PRUEBA)",
    "cheat_menu_close": "Presiona ESC o haz clic en X para cerrar",
    "cheat_tab_waves": "1. Oleadas",
    "cheat_tab_power": "2. Poder",
    "cheat_tab_stats": "3. Estadísticas",
    "cheat_tab_perma": "4. Permanente",
    "cheat_tab_enemies": "5. Enemigos",
    "cheat_current_wave": "Oleada Actual:",
    "cheat_waves_until_boss": "Oleadas Hasta Jefe:",
    "cheat_enemies_alive": "Enemigos vivos:",
    "cheat_skip_wave": "Omitir Oleada Actual",
    "cheat_advance_wave": "Avanzar a Siguiente Oleada",
    "cheat_trigger_boss": "Activar Oleada de Jefe",
    "cheat_activate_consumable": "Haz clic para activar consumible (30 segundos)",
    "cheat_speed_boost": "Impulso de Velocidad",
    "cheat_invincibility": "Invencibilidad",
    "cheat_fire_rate": "Cadencia de Fuego",
    "cheat_magnet": "Imán",
    "cheat_player_stats": "Estadísticas del Jugador (Haz clic en botones para modificar)",
    "cheat_health": "Salud:",
    "cheat_max_health": "Salud Máxima:",
    "cheat_coins": "Monedas:",
    "cheat_speed": "Velocidad:",
    "cheat_health_full": "Lleno",
    "cheat_health_half": "Mitad",
    "cheat_health_low": "Bajo",
    "cheat_health_num": "100",
    "cheat_speed_normal": "Normal",
    "cheat_speed_fast": "Rápido",
    "cheat_speed_max": "Máximo",
    "cheat_modify_stats": "Consejo: Modifica las estadísticas para probar diferentes escenarios",
    "cheat_power_ups_available": "Mejoras Permanentes (Haz clic para agregar/mejorar)",
    "cheat_currently_owned": "Actualmente Poseído:",
    "cheat_none": "Ninguno",
    "cheat_all_power_ups": "Todas las Mejoras Disponibles (desplázate con ARRIBA/ABAJO):",
    "cheat_active_enemies": "Enemigos Activos",
    "cheat_no_enemies": "Sin enemigos actualmente vivos",
    "cheat_discovery_codex": "Códice de Descubrimiento:",
    "cheat_discover_all": "Descubrir Todas las Mejoras",
    "cheat_undiscover_all": "Olvidar Todas las Mejoras",

    # Power-up Installer
    "power_up_installer_title": "INSTALADOR DE MEJORA LEGENDARIA",
    "power_up_installer_title_generic": "ADMINISTRADOR DE ACTUALIZACIÓN DE PROCESOS",
    "power_up_upgrade_tier": "NIVEL DE ACTUALIZACIÓN:",
    "power_up_installer_close": "X",
    "power_up_select_upgrade": "v SELECCIONA MEJORA PARA INSTALAR:",
    "power_up_rolling": "[!] GIRANDO...",
    "power_up_reroll_options": "[R] Opción de Nuevo Intento",
    "power_up_all_installed": "TODOS LOS PAQUETES INSTALADOS",
    "power_up_all_installed_msg": "Carga máxima alcanzada. Todas las mejoras disponibles ya están instaladas.",
    "power_up_continue": "CONTINUAR",
    "power_up_new_badge": "NUEVO",

    # Player Feedback
    "player_dodge": "¡ESQUIVA!",
    "player_parry": "¡PARRY!",
    "player_phase": "¡CAMBIO DE FASE!",
    "player_veil": "¡VELO!",
    "player_blood_pact": "¡PACTO DE SANGRE!",
    "player_conduit": "¡CONDUCTO!",
    "player_aftershock": "¡RÉPLICA!",
    "player_nova": "¡NOVA!",
    "player_nova_cooldown": "¡BALAS LIBERADAS!",
    "player_ability_on_cooldown": "NO DISPONIBLE",

    # System Messages
    "system_defensive_processes": "Todos los procesos defensivos han sido terminados.",
    "system_press_any_key": "Presiona cualquier tecla para continuar...",
    "bios_fast_boot": "Presiona cualquier tecla para arranque rápido",
    "system_no_statistics": "No hay estadísticas disponibles",
    "system_press_esc_to_return": "Presiona ESC para volver",

    # Loading Screen
    "loading_title": "TopHat-ShooterOS",
    "loading_subtitle": "Edición v6.1",
    "loading_initializing": "Inicializando...",
    "loading_generating_sound": "Generando sonido",
    "loading_generating_music": "Generando música",
    "loading_complete": "¡Generación de assets completa!",
    "loading_hint": "Generando assets de audio procedurales",
    "loading_cached": "Todos los assets cargados desde caché",

    # Cheat Menu Buttons
    "cheat_close_instruction": "Presiona ESC o haz clic en X para cerrar",
    "cheat_showing_items": "Mostrando",
    "cheat_scroll_up": "ARRIBA para desplazarse hacia arriba",
    "cheat_scroll_down": "ABAJO para desplazarse hacia abajo",
    "cheat_no_power_ups_selected": "Sin mejoras seleccionadas",

    # OS Task Manager / System Monitoring
    "os_running_processes": "PROCESOS ACTIVOS",
    "os_no_active_processes": "Sin procesos",
    "os_process_name": "Proceso",
    "os_version": "Versión",
    "os_status": "Estado",
    "os_system_performance": "RENDIMIENTO",
    "os_system_manager": "Admin. Sistema",

    # OS Desktop / System Info
    "os_system_monitor": "Monitor del Sistema",
    "os_cpu_idle": "CPU: Inactiva",
    "os_memory": "Memoria",  # label only; live "<used> / <total> GB" appended in code
    "os_network": "Red: Conectada",
    "os_tophat_os": "TopHat-ShooterOS",
    "os_edition": "[Edición v6.1]",
    "os_tophat_button": "TopHat",
    "os_net_indicator": "RED",

    # Stats Labels
    "stats_system_analytics": "Análisis del Sistema",
    "stats_run_report": "Informe de Ejecución",
    "stats_wave_label": "Oleada",
    "stats_time_label": "TIEMPO",
    "stats_kills_label": "BAJAS",
    "stats_avg_dps": "DPS PROM",
    "stats_play_style_balanced": "Equilibrado",
    "stats_no_power_ups_selected": "Sin mejoras seleccionadas",
    "stats_bar_wave_max": "[OLEADA] Máximo Alcanzado",
    "stats_bar_kill_best": "[MUERTES] Mejor Rendimiento",
    "stats_bar_boss_eliminated": "[JEFE] Eliminado",
    "stats_bar_time_survival": "[TIEMPO] Supervivencia Más Larga",
    "stats_host_default": "Host",

    # Enemy Labels
    "enemy_active_threats": "AMENAZAS ACTIVAS:",

    # General
    "general_yes": "Sí",
    "general_no": "No",
    "general_back": "Volver",
    "general_confirm": "Confirmar",
    "general_cancel": "Cancelar",

    # Wave Celebration
    "wave_cleared_text": "OLEADA",
    "boss_defeated_text": "JEFE",
    "wave_celeb_kills": "Muertes",
    "wave_celeb_accuracy": "Precisión",
    "wave_celeb_time": "Tiempo",
    "wave_celeb_coins": "Monedas Ganadas",
    "wave_celeb_max_combo": "Combo Máximo",

    # Real-time stats overlay
    "real_stats_power": "Poder",
    "real_stats_dps": "DPS",
    "real_stats_kills": "Muertes",
    "real_stats_cpm": "M/min",

    # Combo display
    "combo_insane": "¡LOCURA!",
    "combo_crazy": "¡BRUTAL!",
    "combo_sick": "¡ÉPICO!",
    "combo_label": "¡COMBO!",
    "combo_perfect_wave": "¡OLEADA PERFECTA!",
    "combo_perfect_streak": "PERFECTA x",
    "combo_coins": "monedas!",

    # Micro-reward popups & wave-stats
    "massacre_bonus": "¡BONO MASACRE!",
    "wave_stats_flawless": "¡IMPECABLE!",
    "wave_stats_title": "OLEADA",
    "wave_stats_kills_label": "Muertes:",
    "wave_stats_time_label": "Tiempo:",

    # 3D Boss Game HUD
    "game3d_hp": "HP",
    "game3d_ammo": "Balas",
    "game3d_boss_hp": "HP Jefe",
    "game3d_phase": "FASE",
    "game3d_satellites": "Satélites",
    "game3d_destroy_all": "¡DESTRUYE TODOS!",
    "game3d_phase_transition": "¡CAMBIO DE FASE!",
    "game3d_paused": "PAUSA",
    "game3d_press_esc_resume": "Presiona ESC para continuar",

    # OS UI
    "os_root_prompt": "root@tophat-shooteros:~$",
    "os_loading": "Cargando...",
    "os_shop_navigate": "ARRIBA/ABAJO/W/S ",
    "os_shop_select": "ENTER/CLIC ",
    "os_shop_exit": "ESC ",
    "shop_available_balance": "Saldo Disponible",
    "os_system_paused": "Sistema pausado",
    "os_press_space_continue": "presiona ESPACIO para continuar",

    # PvP Lobby
    "pvp_title": "MODO PVP",
    "pvp_host_game": "HOSTEAR",
    "pvp_join_game": "UNIRSE",
    "pvp_configure_hosting": "CONFIG",
    "pvp_nickname": "Apodo:",
    "pvp_max_players": "Máx. Jugadores:",
    "pvp_show_ips": "Mostrar IPs",
    "pvp_enable_interpolation": "Interpolación",
    "pvp_teams_mode": "Modo Equipos",
    "pvp_enable_teams": "Modo Equipos",
    "pvp_num_teams": "Num. Equipos:",
    "pvp_start_hosting": "INICIAR",
    "pvp_hosting_game": "HOSTEANDO",
    "pvp_local_ip": "IP Local:",
    "pvp_port": "Puerto:",
    "pvp_players_count": "Jugadores:",
    "pvp_click_assign_team": "Clic: asignar equipo",
    "pvp_you_host": " (Tú - Host)",
    "pvp_connected_players": "Jugadores:",
    "pvp_teams_enabled": "Equipos: ON",
    "pvp_show_ip": "Mostrar IP",
    "pvp_join_game_title": "UNIRSE",
    "pvp_host_ip": "IP del Host:",
    "pvp_click_cycle_tabs": "Clic: editar | Tab: cambiar",
    "pvp_connect": "CONECTAR",
    "pvp_connecting": "CONECTANDO...",
    "pvp_please_wait": "Espera",
    "pvp_timeout_in": "Timeout:",
    "pvp_game_lobby": "LOBBY",
    "pvp_connected_label": "Conectados:",
    "pvp_click_badge_team": "(clic: cambiar equipo)",
    "pvp_you": " (Tú)",
    "pvp_start_game": "COMENZAR",
    "pvp_need_2_players": "MIN. 2 JUGADORES",
    "pvp_connected": "CONECTADO",
    "pvp_waiting_for_host": "Esperando host...",
    "pvp_players_in_lobby": "En lobby:",
    "pvp_connection_error": "ERROR",
    "pvp_back": "VOLVER",
    "pvp_player_num": "Jugador ",
    "pvp_failed_start_host": "Error host: ",
    "pvp_failed_connect": "Error: ",
    "pvp_connection_timeout": "Timeout",
    "pvp_host_disconnected": "Host caído",

    # PvP Config - Game Stats section
    "pvp_game_stats": "STATS DE PARTIDA",
    "pvp_stat_hp": "HP",
    "pvp_stat_kill_limit": "LÍM. BAJAS",
    "pvp_stat_respawn": "RESPAWN (s)",
    "pvp_stat_speed": "VEL.",
    "pvp_stat_damage": "DAÑO",
    "pvp_stat_fire_rate": "CADENCIA (s)",
    "pvp_stat_bullet_speed": "VEL. BALA",
    "pvp_stat_bullet_radius": "TAM. BALA",
    "pvp_stat_start_walls": "MUROS INI.",
    "pvp_stat_time_limit": "LÍM. TIEMPO",
    "pvp_stat_net_quality": "CALIDAD RED",
    "pvp_net_quality_ultra": "Ultra (128 ticks)",
    "pvp_net_quality_high": "Alta (64 ticks)",
    "pvp_net_quality_medium": "Media (32 ticks)",
    "pvp_net_quality_low": "Baja (20 ticks)",
    "pvp_value_off": "OFF",
    "pvp_local_net_multiplayer": "[ RED LOCAL MULTIJUGADOR ]",
    "pvp_share_ip_info": "Comparte tu IP local con amigos en la misma red",

    # PvP Teams
    "pvp_team_red": "Rojo",
    "pvp_team_blue": "Azul",
    "pvp_team_green": "Verde",
    "pvp_team_yellow": "Amarillo",
    "pvp_team_orange": "Naranja",
    "pvp_team_purple": "Púrpura",
    "pvp_team_none": "Ninguno",

    # Lifetime Stats Labels
    "stats_movement_label": "MOVIMIENTO",
    "stats_distance_label": "Distancia",
    "stats_phase_shifts_label": "Cambios de Fase",
    "stats_time_warps_label": "Distorsiones Temporales",
    "stats_near_deaths_label": "Casi Muertes",
    "stats_best_streak_label": "Mejor Racha",
    "stats_time_low_hp_label": "Tiempo HP Bajo",
    "stats_performance_label": "RENDIMIENTO",
    "stats_peak_dps_label": "DPS Máximo",
    "stats_avg_dps_label": "DPS Promedio",
    "stats_kills_min_label": "Muertes/Min",
    "stats_avg_wave_label": "Oleada Promedio",
    "stats_fast_wave_label": "Oleada Rápida",
    "stats_resources_label": "RECURSOS",
    "stats_coins_earned_label": "Monedas Ganadas",
    "stats_coins_spent_label": "Monedas Gastadas",
    "stats_coins_saved_label": "Monedas Ahorradas",
    "stats_walls_placed_label": "Muros Colocados",
    "stats_consumables_label": "Consumibles",
    "stats_shop_purchases_label": "Compras en Tienda",
    "stats_play_style_label": "ESTILO DE JUEGO",
    "stats_aggression_label": "Agresión",
    "stats_caution_label": "Precaución",
    "stats_no_powerups_selected": "Sin mejoras seleccionadas",
    "stats_dps_over_time_label": "DPS A TRAVÉS DEL TIEMPO",
    "stats_no_graph_data_short": "Sin datos de gráfico",
    "stats_controls_footer": "[TAB/ESC] Volver  [R] Reiniciar  [Q] Menú",
    "stats_play_style_aggressive": "Agresivo",
    "stats_play_style_defensive": "Defensivo",
    "stats_play_style_mobile": "Móvil",
    "stats_play_style_tank": "Tanque",

    # Gamemode Names and Descriptions
    "gamemode_wave_based_name": "Por Oleadas",
    "gamemode_wave_based_desc": "Lucha contra oleadas de enemigos. Derrota a los jefes cada 5 oleadas para obtener mejoras legendarias.",
    "gamemode_time_survival_name": "Supervivencia por Tiempo",
    "gamemode_time_survival_desc": "Sobrevive el mayor tiempo posible. La dificultad aumenta con el tiempo.",
    "gamemode_sandbox_name": "Sandbox",
    "gamemode_sandbox_desc": "Prueba y experimenta con enemigos, jefes y mecánicas del juego.",
    "gamemode_pvp_name": "PVP",
    "gamemode_pvp_desc": "¡Batalla en tiempo real. Primero en 5 bajas gana!",
    "gamemode_roguelite_name": "Roguelite",
    "gamemode_roguelite_desc": "Explora 4 pisos temáticos, consigue llaves y reliquias, vence jefes de piso y guarda fragmentos.",
    "roguelite_setup_title": "AJUSTE DE MAZMORRA",
    "roguelite_setup_subtitle": "CONFIGURA EQUIPO  //  ELIGE KIT  ·  AJUSTA CALOR  ·  INICIA",
    "roguelite_unlocks_title": "DESBLOQUEOS",
    "roguelite_data_shards": "Fragmentos",
    "roguelite_shards": "Frag.",
    "roguelite_shards_short": "frag.",
    "roguelite_cores": "Núcleos",
    "roguelite_cores_short": "Núcleos",
    "roguelite_heat": "Calor",
    "roguelite_floor": "Piso",
    "roguelite_level_up": "¡SUBIÓ DE NIVEL!",
    "roguelite_endless": "Infinito",
    "roguelite_pressure": "Presión",
    "roguelite_elite": "Élite",
    "dungeon_rooms": "Salas",
    "dungeon_rooms_cleared": "Salas Limpiadas",
    "dungeon_keys": "Llaves",
    "dungeon_door_locked": "BLOQUEADA - busca una llave",
    "dungeon_door_unlock": "Usar llave para abrir",
    "dungeon_shop_prompt": "[E] Abrir tienda",
    "dungeon_portal_prompt": "Entra al portal para descender",
    "dungeon_floor_select_title": "ELIGE TEMA DEL PISO",
    "dungeon_floor_select_tip": "Cada tema tiene sus propios procesos, peligros y jefe de piso. Los temas usados no se repiten en la ejecución.",
    "roguelite_victory_title": "SISTEMA PURGADO",
    "roguelite_victory_subtitle": "Todos los jefes de piso han caído. El SO es tuyo: retírate con tu botín o lleva al núcleo más hondo en el bucle infinito.",
    "roguelite_loop_cleared_title": "BUCLE COMPLETADO",
    "roguelite_loop_cleared_subtitle": "Otro bucle asegurado. Guarda tu botín o desciende de nuevo por recompensas mayores y procesos más feroces.",
    "roguelite_relics_carried": "Reliquias llevadas",
    "roguelite_relics_none": "Sin reliquias esta ejecución.",
    "roguelite_continue_endless": "Continuar (Bucle Infinito)",
    "roguelite_cash_out": "Retirarse",
    "roguelite_victory_controls": "[ESPACIO] continuar    [ESC] retirarse    [←/->] cambiar    [ENTER] confirmar",
    "dungeon_floor_boss": "Jefe del Piso",
    "dungeon_final_floor_label": "JEFE FINAL",
    "dungeon_final_floor_desc": "La pila termina aquí. No quedan sectores que sortear, solo el último proceso. Entra a la arena y enfréntate a la Entidad Omega.",
    "dungeon_final_floor_warning": "No más sectores. No hay vuelta atrás.",
    "dungeon_theme_firewall": "Cortafuegos",
    "dungeon_theme_firewall_desc": "Red defensiva endurecida. Tiradores y bloqueadores constantes en cada sala.",
    "dungeon_theme_recycle_bin": "Papelera",
    "dungeon_theme_recycle_bin_desc": "Enjambres de procesos desechados. Perseguidores débiles con estrellas tanque.",
    "dungeon_theme_registry": "Registro",
    "dungeon_theme_registry_desc": "Asesinos ordenados. Cruces y cubos con ráfagas precisas.",
    "dungeon_theme_network": "Red",
    "dungeon_theme_network_desc": "Tráfico de paquetes. Embestidores, snipers y golpes rápidos.",
    "dungeon_theme_kernel": "Núcleo",
    "dungeon_theme_kernel_desc": "Espacio profundo del sistema. Unidades pesadas y magos con potencia real.",
    "dungeon_theme_cache": "Caché",
    "dungeon_theme_cache_desc": "Memoria reflejada. Fantasmas, embaucadores y caos teletransportado.",
    "dungeon_theme_corrupted_sector": "Sector Corrupto",
    "dungeon_theme_corrupted_sector_desc": "Todo vale. Todos los procesos, más élites y las mayores recompensas.",
    "roguelite_best": "Récord",
    "roguelite_kits": "Kits",
    "roguelite_families": "Familias",
    "roguelite_relics": "Reliquias",
    "roguelite_unlocked": "COMPRADO",
    "roguelite_locked": "BLOQUEADO",
    "roguelite_unlock_hint": "Gasta fragmentos",
    "roguelite_unlocks": "[U] Tienda",
    "roguelite_start": "[ENTER] Iniciar",
    "roguelite_back": "[ESC] Volver",
    "roguelite_setup_controls": "Kit A/D  |  Calor W/S  |  Tienda U  |  Iniciar ENTER",
    "roguelite_sector_controls": "Tema A/D  |  Entrar ENTER",
    "roguelite_unlock_controls": "Volver ESC/U",
    "roguelite_unlock_shop_controls": "Grupo TAB/A-D  |  Item W/S  |  Comprar ENTER  |  Volver ESC",
    "roguelite_scroll_hint": "Rueda para ver más",
    "roguelite_unlock_shop_hint": "Gasta fragmentos y núcleos de Calor alto. Los desbloqueos tardíos requieren economías de Calor 2+.",
    "roguelite_unlock_categories": "GRUPOS",
    "roguelite_unlock_details": "DETALLES",
    "roguelite_unlock_cat_kits": "Kits",
    "roguelite_unlock_cat_families": "Familias",
    "roguelite_unlock_cat_relics": "Reliquias",
    "roguelite_unlock_cat_challenge": "Desafío",
    "roguelite_cost": "Costo",
    "roguelite_ready_to_buy": "LISTO",
    "roguelite_not_enough_shards": "FALTAN RECURSOS",
    "roguelite_buy_unlock": "[ENTER] COMPRAR",
    "roguelite_need_more_shards": "FALTAN RECURSOS",
    "roguelite_already_unlocked": "COMPRADO",
    "roguelite_unlock_heat": "Calor",
    "roguelite_unlock_wave_surge": "Oleada Extra",
    "roguelite_unlock_desc_wave_surge": "Cambia cada jefe de piso por una versión más dura por nivel, con mayores recompensas.",
    "roguelite_wave_surge": "Oleada Extra",
    "roguelite_unlock_desc_family": "Añade esta familia a los drafts futuros.",
    "roguelite_unlock_desc_family_core": "Añade mejoras base de estadísticas, balas, economía y supervivencia.",
    "roguelite_unlock_desc_family_shield": "Añade armadura, muros, espinas y herramientas de escudo.",
    "roguelite_unlock_desc_family_arcane": "Añade Aura Arcana, Balas Arcanas, Ecos, Gravedad y Sobrecarga.",
    "roguelite_unlock_desc_family_fire": "Añade aura de fuego, balas de fuego, orbe y Dominio del Fuego.",
    "roguelite_unlock_desc_family_frost": "Añade disparos lentos, orbe de hielo y Dominio de Escarcha.",
    "roguelite_unlock_desc_family_poison": "Añade aura, disparos, orbe y Dominio del Veneno.",
    "roguelite_unlock_desc_family_lightning": "Añade aura/orbe eléctrico, Cadena, Conducto y dominio.",
    "roguelite_unlock_desc_family_wind": "Añade aura/balas/orbe de viento, Réplica y Dominio del Viento.",
    "roguelite_unlock_desc_family_blood": "Añade robo de vida, armas de sangre, Pacto y Dominio.",
    "roguelite_unlock_desc_discount": "Reliquia: los rerolls cuestan un 20% menos, mínimo 5 créditos.",
    "roguelite_unlock_desc_shard": "Reliquia: +25% de fragmentos por salas limpiadas.",
    "roguelite_unlock_desc_draft": "Reliquia: los rerolls cuestan 10 créditos menos tras descuentos.",
    "roguelite_unlock_desc_patch": "Reliquia: cada jefe de piso cura 2 HP y da +1 carga de escudo.",
    "roguelite_unlock_desc_elite": "Reliquia: las salas élite dan +30 créditos y fragmentos extra.",
    "roguelite_unlock_desc_heat": "Desbloquea el siguiente nivel de Calor sobre el valor base. Calor 3 cuesta Núcleos ganados en Calor 2+.",
    "roguelite_starter_ready": "LISTO",
    "roguelite_boss": "Jefe",
    "roguelite_boss_tier": "Oleada Extra",
    "roguelite_recursion": "Recursión",
    "roguelite_recursion_dmg": "DAÑO PERM.",
    "roguelite_level": "Niv",
    "roguelite_run_flow": "RUTA DE PISOS",
    "roguelite_combat_title": "PISO DE MAZMORRA",
    "roguelite_heat_effects": "Efectos",
    "roguelite_heat_unlock_first": "El Calor 1 está desbloqueado por defecto.",
    "roguelite_heat_unlock_next": "Compra Calor",
    "roguelite_heat_buy_next": "Comprar Calor",
    "roguelite_heat_maxed": "Calor al maximo",
    "roguelite_heat_unlock_rule": "El Calor 1 es el valor base. El Calor 2 y 3 suman presión, élites, apariciones más rápidas, jefes más duros, más fragmentos y núcleos exclusivos.",
    "roguelite_heat_core_rule": "El Calor 2+ da Núcleos. El Calor 3 da muchos más.",
    "roguelite_req_default": "Inicial",
    "roguelite_req_35_act2": "35 fragmentos o Piso 2",
    "roguelite_req_75_act3": "75 fragmentos o Piso 3",
    "roguelite_req_125_win": "125 fragmentos o 1 victoria",
    "roguelite_req_200_heat2_endless1": "200 fragmentos, Calor 2 o Infinito 1",
    "roguelite_req_300_endless2": "300 fragmentos o Infinito 2",
    "roguelite_kit_operator": "Operador",
    "roguelite_kit_bulwark": "Baluarte",
    "roguelite_kit_arcanist": "Arcanista",
    "roguelite_kit_operator_desc": "Empieza con 15 creditos y sin mejora fija.",
    "roguelite_kit_bulwark_desc": "Empieza con 5 creditos, +3 muros y armadura Fortificada.",
    "roguelite_kit_arcanist_desc": "Empieza con Balas Arcanas y 0 creditos.",
    "roguelite_family_core": "Base",
    "roguelite_family_shield": "Escudo",
    "roguelite_family_arcane": "Arcano",
    "roguelite_family_fire": "Fuego",
    "roguelite_family_frost": "Hielo",
    "roguelite_family_poison": "Veneno",
    "roguelite_family_lightning": "Rayo",
    "roguelite_family_wind": "Viento",
    "roguelite_family_blood": "Sangre",
    "roguelite_relic_none": "Ninguna",
    "roguelite_relic_discount": "Protocolo Descuento",
    "roguelite_relic_shard": "Imán de Fragmentos",
    "roguelite_relic_elite": "Dividendo Elite",
    "roguelite_relic_patch": "Parche de Emergencia",
    "roguelite_relic_draft": "Caché de Selección",
    "roguelite_no_run": "No hay ejecución roguelite activa.",
    "roguelite_no_profile": "No hay perfil roguelite cargado.",
    "roguelite_beta_banner": "BETA - EN DESARROLLO",
    "stats_tab_roguelite": "Roguelite",
    "stats_roguelite_metrics": "MÉTRICAS ROGUELITE",
    "stats_roguelite_best_sectors": "Mejores Salas",
    "stats_roguelite_runs": "Ejecuciones",
    "stats_roguelite_lifetime": "ROGUELITE TOTAL",
    "stats_roguelite_mode": "Roguelite",

    # Enemy Names and Descriptions
    "enemy_circle_name": "Perseguidor",
    "enemy_circle_desc": "Enemigo cuerpo a cuerpo básico",
    "enemy_pentagon_name": "Francotirador",
    "enemy_pentagon_desc": "Disparo único preciso y veloz",
    "enemy_triangle_name": "Zigzagueador",
    "enemy_triangle_desc": "Rápido con movimiento errático y embates",
    "enemy_star_name": "Tanque Estrella",
    "enemy_star_desc": "Resistente, requiere varios impactos",
    "enemy_cube_name": "Tirador",
    "enemy_cube_desc": "Mantiene distancia y dispara ráfagas de 3",
    "enemy_hexagon_name": "Teletransportador",
    "enemy_hexagon_desc": "Se teleporta y dispara patrones caóticos",
    "enemy_cross_name": "Embistidor",
    "enemy_cross_desc": "Avisa antes del ataque de láser giratorio",
    "enemy_diamond_name": "Diamante",
    "enemy_diamond_desc": "Dispara proyectiles mientras embiste",
    "enemy_octagon_name": "Dispersador",
    "enemy_octagon_desc": "Alto ritmo de fuego, baja precisión",
    "enemy_trickster_name": "Embaucador",
    "enemy_trickster_desc": "Muestra avisos falsos y se teleporta",
    "enemy_phantom_name": "Fantasma",
    "enemy_phantom_desc": "Se teleporta y crea clones falsos",
    "enemy_sniper_name": "Sniper",
    "enemy_sniper_desc": "Carga un disparo letal de un golpe",
    "enemy_mage_name": "Mago",
    "enemy_mage_desc": "Invoca meteoritos y dispara proyectiles teledirigidos",

    # Boss Names and Descriptions
    "boss_1_name": "El Guardián Espiral",
    "boss_1_desc": "Entidad mística que teje patrones de espiral",
    "boss_2_name": "El Rey Invocador",
    "boss_2_desc": "Abruma con ejércitos de secuaces",
    "boss_3_name": "El Azote Meteórico",
    "boss_3_desc": "Lluvia de destrucción desde las alturas",
    "boss_4_name": "El Arquitecto Láser",
    "boss_4_desc": "Construye trampas letales de rejillas láser",
    "boss_5_name": "El Danzante del Vacío",
    "boss_5_desc": "Parpadea entre dimensiones dejando energía oscura",
    "boss_6_name": "El Reactor en Cadena",
    "boss_6_desc": "Ser de pura electricidad que encadena arcos devastadores",
    "boss_7_name": "El Comandante Orbital",
    "boss_7_desc": "Controla satélites que atacan con precisión astronómica",
    "boss_8_name": "El Berserker Imparable",
    "boss_8_desc": "Fuerza de ira pura que se fortalece al sangrar",
    "boss_9_name": "El Arquitecto Prisma",
    "boss_9_desc": "Manipula la luz en prisiones geométricas de láseres",
    "boss_10_name": "El Cronómetra",
    "boss_10_desc": "Dobla el tiempo creando paradojas y grietas temporales",
    "boss_11_name": "El Tejedor del Caos",
    "boss_11_desc": "Teje patrones de caos puro, imprevisible y devastador",
    "boss_12_name": "La Entidad Omega",
    "boss_12_desc": "El desafío final: combina todos los mecánicos anteriores",

    # Exit Confirm Dialog
    "confirm_quit_title": "CONFIRMAR SALIDA",
    "confirm_exit_title": "CONFIRMAR VUELTA",
    "confirm_quit_body": "¿Cerrar TopHat-ShooterOS?",
    "confirm_exit_body": "¿Volver al menú principal?",
    "confirm_unsaved": "El progreso no guardado se perderá.",
    "confirm_cancel_btn": "[ESC] CANCELAR",
    "confirm_quit_btn": "[Q] SALIR",
    "confirm_exit_btn": "[Q] VOLVER",
    "confirm_checkpoint_title": "PUNTO DE CONTROL DISPONIBLE",
    "confirm_checkpoint_restart_body": "¿Reiniciar desde la oleada 1?",
    "confirm_checkpoint_sub": "Todavía puedes CONTINUAR desde tu último punto de control.",
    "confirm_restart_btn": "[R] REINICIAR",

    # Common
    "common_on": "ACT.",
    "common_off": "DESACT.",

    # Boss threat HUD
    "boss_threat_critical": "AMENAZA CRÍTICA",
    "boss_threat_phase_header": "FASE",
    "boss_threat_phase_name": "Fase",
    "boss_threat_breached": "SUPERADA",
    "boss_threat_locked": "BLOQUEADA",
    "boss_phase_firewall": "FIREWALL DE FASE",
    "enemy_sealed_clear_adds": "SELLADO - ELIMINA REFUERZOS",
    "enemy_overload_hold_fire": "SOBRECARGA - ALTO EL FUEGO",

    # Sandbox power-up visuals tab
    "sandbox_powerup_visuals": "Visuales de Mejoras",
    "sandbox_visuals_subtitle": "Vista previa de icono, rareza y descripción Nv.1",
    "sandbox_badge_legendary": "LEGENDARIA",
    "sandbox_badge_common": "COMÚN",
    "sandbox_lv1_preview": "Vista previa Nv.1",
    "sandbox_badge_locked": "BLOQUEADO",
    "sandbox_powerup_locked_name": "??? No Descubierto",
    "sandbox_powerup_locked_desc": "Bloqueado. Descubre esta mejora en una partida para revelar sus detalles.",
    "sandbox_enter_boss_3d": "Entrar Jefe #7 3D",
    "sandbox_test_3d_arena": "Probar Arena 3D",

    # Advancements window
    "adv_control_title": "CONTROL DE LOGROS",
    "adv_sync_desc": "Progresión persistente sincronizada con estadísticas totales, últimas partidas y datos del perfil roguelite. Reclama logros para ganar Fragmentos de Datos.",
    "adv_unlocked_count": "Desbloqueados",
    "adv_claimed_count": "Reclamados",
    "adv_shard_balance": "Fragmentos de Datos",
    "adv_claim_all": "Reclamar Todo +",
    "adv_all_claimed": "Todo Reclamado",
    "adv_categories": "Categorías",
    "adv_detail": "Detalle",
    "adv_progress": "Progreso",
    "adv_status": "Estado",
    "adv_reward": "Recompensa",
    "adv_unlocked_at": "Desbloqueado",
    "adv_reward_claimed": "Recompensa Reclamada",
    "adv_claim_reward": "Reclamar Recompensa",
    "adv_locked_btn": "Bloqueado",
    "adv_tier_legend": "Rareza",
    "adv_category_label": "Categoría",

    # Stats window leftovers
    "stats_healing_sources": "Fuentes de Curación",
    "stats_health_consumable": "Consumible de Salud",
    "stats_no_healing_data": "Sin datos de curación",
    "stats_total_earned": "Total Ganado",
    "stats_analytics_report": "Análisis del Sistema - Informe",

    # Desktop
    "desktop_net": "RED",
    "desktop_advancement_unlocked": "Logro desbloqueado",
    "desktop_mode_locked": "MODO BLOQUEADO:",
    "survival_locked_desc": "Desbloquea Supervivencia en Tiempo derrotando el modo Roguelite.",
    "roguelite_locked_desc": "Desbloquea Roguelite derrotando el jefe de la Ola 20 en Modo de Olas.",
    "game_mode_unlocked": "NUEVO MODO DESBLOQUEADO:",
    "roguelite_unlocked_notif": "¡El Modo Roguelite ya está disponible en el escritorio!",
    "survival_unlocked_notif": "¡El Modo Supervivencia ya está disponible en el escritorio!",

    # Debug panel runtime stats
    "debug_panel_dps": "DPS",
    "debug_panel_cmin": "M/min",
    "debug_panel_abilities": "HABILIDADES",

    # Cheat / debug menu (new keys)
    "cheat_lv": "Nv",
    "cheat_remove": "Quitar",
    "cheat_alive": "vivos",
    "cheat_of": "de",
    "cheat_more_enemies": "enemigos más...",
    "cheat_custom_boss": "JEFE PERSONALIZADO",
    "cheat_enemy_environment": "Entorno",
    "cheat_cons_health": "Salud",
    "cheat_cons_coin": "Moneda",
    "cheat_cons_shield": "Impulso de Escudo",
    "cheat_cons_damage": "Impulso de Daño",
    "cheat_cons_double_coin": "Moneda Doble",
    "cheat_cons_lifesteal": "Robo de Vida",

    # Comeback mechanic
    "comeback_bonus_active": "REGRESO +10%",
    "comeback_bonus_until": "hasta oleada",

    # Settings
    "settings_replay_mode_intros": "Repetir Intros de Modo",

    # Mode intro: wave-based
    "mode_intro_wave_title": "EN DIRECTO // RESPUESTA A AMENAZA",
    "mode_intro_wave_rec1":  "BARRIDO DE RADAR",
    "mode_intro_wave_1a":    "LA BRECHA ESTÁ ABIERTA. LA CORRUPCIÓN IRRUMPE.",
    "mode_intro_wave_1b":    "PROTOCOLO DE DEFENSA POR OLEADAS ACTIVADO",
    "mode_intro_wave_rec2":  "DESPLIEGUE",
    "mode_intro_wave_2a":    "CADA OLEADA APRENDE. CADA OLEADA SE ACERCA.",
    "mode_intro_wave_2b":    "AGUANTA LA LÍNEA, OPERADOR.",

    # Mode intro: time survival
    "mode_intro_surv_title": "EN DIRECTO // LA LARGA VIGILIA",
    "mode_intro_surv_rec1":  "CUENTA REGRESIVA",
    "mode_intro_surv_1a":    "LA RAÍZ FUE PURGADA. LA MAREA SIGUE LLEGANDO.",
    "mode_intro_surv_1b":    "LA LARGA VIGILIA COMIENZA.",
    "mode_intro_surv_rec2":  "REGISTRO DE TIEMPO",
    "mode_intro_surv_2a":    "CADA SEGUNDO DE ACTIVIDAD QUEDA REGISTRADO.",
    "mode_intro_surv_2b":    "NO VENDRÁN REFUERZOS. AGUANTA IGUAL.",

    # Mode intro: roguelite
    "mode_intro_rogue_title": "EN DIRECTO // RECUPERACIÓN PROFUNDA",
    "mode_intro_rogue_rec1":  "MAPA DE LA PILA",
    "mode_intro_rogue_1a":    "LA SUPERFICIE ESTÁ ASEGURADA. LA PODREDUMBRE AÚN LATE ABAJO.",
    "mode_intro_rogue_1b":    "DESCIENDE LA PILA, SECTOR A SECTOR.",
    "mode_intro_rogue_rec2":  "ESCANEO DE RELIQUIA",
    "mode_intro_rogue_2a":    "RECUPERA PROCESOS PERDIDOS DEL KERNEL. RECLAMA RELIQUIAS.",
    "mode_intro_rogue_2b":    "ENCUENTRA AQUELLO DE LO QUE NACIÓ LA RAÍZ.",

    # Mode intro: sandbox
    "mode_intro_sandbox_title": "FUERA DE REGISTRO // ENTORNO DE PRUEBAS",
    "mode_intro_sandbox_rec1":  "SECUENCIA DE INICIO",
    "mode_intro_sandbox_1a":    "ENTORNO DE PRUEBAS ACTIVO",
    "mode_intro_sandbox_1b":    "ADVERTENCIA: SIN LIMITACIONES. PROCEDE LIBREMENTE.",

    # Mode intro: pvp
    "mode_intro_pvp_title": "SEÑAL EXTERNA // NODO HOSTIL",
    "mode_intro_pvp_rec1":  "ESCANEO DE RED",
    "mode_intro_pvp_1a":    "NODO HOSTIL DETECTADO",
    "mode_intro_pvp_1b":    "PROTOCOLO DE CONFLICTO MULTI-AGENTE ACTIVADO",
    "mode_intro_pvp_rec2":  "BLOQUEO DE ADVERSARIO",
    "mode_intro_pvp_2a":    "FIRMA DEL ADVERSARIO CONFIRMADA",
    "mode_intro_pvp_2b":    "ELIMINA O SERÁS ELIMINADO.",
    # Mode-exclusive power-up names
    "powerup_glitch_field":    "CAMPO_FALLO.dll",
    "powerup_time_surge":      "OLEADA_TEMPORAL.exe",
    "powerup_last_stand":      "ULTIMA_DEFENSA.sys",
    "powerup_recursion":       "RECURSION.bin",
    "powerup_sector_protocol": "PROTOCOLO_SECTOR.exe",
    # Mode-exclusive power-up descriptions
    "powerup_glitch_field_desc1":   "Las balas tienen un 20% de probabilidad de interferir la navegación enemiga por 0,5s.",
    "powerup_glitch_field_desc2":   "Las balas tienen un 30% de probabilidad de interferir la navegación enemiga por 0,5s.",
    "powerup_glitch_field_desc3":   "Las balas tienen un 40% de probabilidad de interferir la navegación enemiga por 0,5s.",
    "powerup_time_surge_desc1":     "Cada eliminación extiende el temporizador de cadencia de fuego en 0,5s.",
    "powerup_time_surge_desc2":     "Cada eliminación extiende el temporizador de cadencia de fuego en 0,75s.",
    "powerup_time_surge_desc3":     "Cada eliminación extiende el temporizador de cadencia de fuego en 1s.",
    "powerup_last_stand_desc":      "LEGENDARIO: Una vez por vida, sobrevivir a un golpe mortal otorga 3s de invulnerabilidad.",
    "powerup_recursion_desc1":      "+8% de daño permanente.",
    "powerup_recursion_desc2":      "+14% de daño permanente.",
    "powerup_recursion_desc3":      "+20% de daño permanente.",
    "powerup_sector_protocol_desc": "LEGENDARIO: Cada eliminación otorga +1 moneda. Cada nuevo piso otorga +15 monedas.",
    # Stage 5 survival-exclusive names
    "powerup_crisis_mode":          "MODO_CRISIS.dll",
    "powerup_adaptive_firewall":    "FW_ADAPTABLE.exe",
    "powerup_last_transmission":    "ULTIMA_TX.dll",
    "powerup_kill_chain":           "CADENA_MORTAL.exe",
    # Stage 5 survival-exclusive descriptions
    "powerup_crisis_mode_desc1":    "Por debajo del 30% de HP: +15% de daño adicional.",
    "powerup_crisis_mode_desc2":    "Por debajo del 30% de HP: +20% de daño adicional.",
    "powerup_crisis_mode_desc3":    "Por debajo del 30% de HP: +25% de daño adicional.",
    "powerup_adaptive_firewall_desc1": "Recibir un golpe otorga 3s de +25% de velocidad de disparo.",
    "powerup_adaptive_firewall_desc2": "Recibir un golpe otorga 3s de +35% de velocidad de disparo.",
    "powerup_adaptive_firewall_desc3": "Recibir un golpe otorga 3s de +45% de velocidad de disparo.",
    "powerup_last_transmission_desc1": "12% de probabilidad por eliminación de restaurar 0,5 HP.",
    "powerup_last_transmission_desc2": "18% de probabilidad por eliminación de restaurar 0,5 HP.",
    "powerup_last_transmission_desc3": "25% de probabilidad por eliminación de restaurar 0,5 HP.",
    "powerup_kill_chain_desc":      "LEGENDARIO: 5 eliminaciones en 3s desencadenan una onda de choque de 1,5x de daño.",
    # Stage 5 roguelite-exclusive names
    "powerup_corrupted_core":       "NUCLEO_CORRUPTO.dll",
    "powerup_room_echo":            "ECO_SALA.dll",
    "powerup_chain_reaction":       "REACCION_CADENA.dll",
    "powerup_kernel_exploit":       "EXPLOIT_KERNEL.sys",
    # Stage 5 roguelite-exclusive descriptions
    "powerup_corrupted_core_desc1": "Eliminar élites otorga +100 HP máximo.",
    "powerup_corrupted_core_desc2": "Eliminar élites otorga +150 HP máximo.",
    "powerup_corrupted_core_desc3": "Eliminar élites otorga +200 HP máximo.",
    "powerup_room_echo_desc1":      "Al limpiar una sala, obtén 8 balas cargadas con +60% de daño.",
    "powerup_room_echo_desc2":      "Al limpiar una sala, obtén 12 balas cargadas con +60% de daño.",
    "powerup_room_echo_desc3":      "Al limpiar una sala, obtén 16 balas cargadas con +60% de daño.",
    "powerup_chain_reaction_desc1": "20% de probabilidad por eliminación de obtener una moneda extra.",
    "powerup_chain_reaction_desc2": "30% de probabilidad por eliminación de obtener una moneda extra.",
    "powerup_chain_reaction_desc3": "40% de probabilidad por eliminación de obtener una moneda extra.",
    "powerup_kernel_exploit_desc":  "LEGENDARIO: Derrotar a un jefe otorga +20% de daño permanente.",
    "powerup_data_harvest":         "COSECHA_DATOS.dll",
    "powerup_data_harvest_desc1":   "Los enemigos otorgan +25% de XP. +25% de rango de recogida.",
    "powerup_data_harvest_desc2":   "Los enemigos otorgan +50% de XP. +50% de rango de recogida.",
    "powerup_data_harvest_desc3":   "Los enemigos otorgan +100% de XP. +100% de rango de recogida.",
    "resume_run_title":        "PARTIDA GUARDADA ENCONTRADA",
    "resume_run_body":         "Continuar tu partida guardada o empezar una nueva?",
    "resume_continue":         "CONTINUAR",
    "resume_new_run":          "NUEVA PARTIDA",
    "new_process_installed":   "NUEVO PROCESO DESCUBIERTO"
  }.toTable
}.toTable

# Current language (default to English)
var currentLanguage*: Language = English

# Optional callback invoked after language changes, used to refresh any data
# that cached translated strings at initialization time (e.g. skin databases).
var onLanguageChange*: proc() = nil

# Get translation for a key
proc t*(key: string): string =
  ## Get translation for the current language
  if translations.hasKey(currentLanguage) and translations[currentLanguage].hasKey(key):
    return translations[currentLanguage][key]
  # Fallback to English if translation not found
  elif translations.hasKey(English) and translations[English].hasKey(key):
    return translations[English][key]
  else:
    return key  # Return key itself as last resort

# Get translation for a TranslationKey enum
proc t*(key: TranslationKey): string =
  ## Get translation for the current language using enum
  return t($key)

# Set current language
proc setLanguage*(lang: Language) =
  currentLanguage = lang
  if not onLanguageChange.isNil:
    onLanguageChange()

# Get current language
proc getLanguage*(): Language =
  return currentLanguage

# Get language name for display
proc getLanguageName*(lang: Language): string =
  case lang
  of English: "English"
  of Spanish: "Español"
