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
    
    # Settings
    tkSettingsTitle = "settings_title"
    tkSettingsFpsLimit = "settings_fps_limit"
    tkSettingsClickEdit = "settings_click_edit"
    tkSettingsSoundEffects = "settings_sound_effects"
    tkSettingsMusic = "settings_music"
    tkSettingsFullscreen = "settings_fullscreen"
    tkSettingsFullscreenToggle = "settings_fullscreen_toggle"
    tkSettingsShowFps = "settings_show_fps"
    tkSettingsMouseSupport = "settings_mouse_support"
    tkSettingsMouseSupportDesc = "settings_mouse_support_desc"
    tkSettingsShowCursor = "settings_show_cursor"
    tkSettingsShowCursorDesc = "settings_show_cursor_desc"
    tkSettingsDebugPanel = "settings_debug_panel"
    tkSettingsDebugPanelDesc = "settings_debug_panel_desc"
    tkSettingsShowHints = "settings_show_hints"
    tkSettingsShowHintsDesc = "settings_show_hints_desc"
    tkSettingsShowEnemyLabels = "settings_show_enemy_labels"
    tkSettingsShowEnemyLabelsDesc = "settings_show_enemy_labels_desc"
    tkSettingsLanguage = "settings_language"
    tkSettingsBackToMenu = "settings_back_to_menu"
    
    # Settings window tabs and sections
    tkSettingsTabGraphics = "settings_tab_graphics"
    tkSettingsTabAudio = "settings_tab_audio"
    tkSettingsTabControls = "settings_tab_controls"
    tkSettingsTabGameplay = "settings_tab_gameplay"
    
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
    tkStatsPlayStyle = "stats_play_style"
    tkStatsAggression = "stats_aggression"
    tkStatsCaution = "stats_caution"
    tkStatsDPSOverTime = "stats_dps_over_time"
    tkStatsNoGraphData = "stats_no_graph_data"
    tkStatsMaxCombo = "stats_max_combo"
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
    tkHelpEnemiesTopic = "help_enemies_topic"
    tkHelpBossesTopic = "help_bosses_topic"
    tkHelpShopTopic = "help_shop_topic"
    tkHelpClearCommand = "help_clear_command"
    tkHelpCommandSeparator = "help_command_separator"
    tkHelpLaunchTopics = "help_launch_topics"
    tkHelpOpeningSettings = "help_opening_settings"
    tkHelpLaunchingSandbox = "help_launching_sandbox"
    tkHelpShuttingDown = "help_shutting_down"
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
    tkHelpF = "help_f"
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
    
    # Power-up Installer
    tkPowerUpInstallerTitle = "power_up_installer_title"
    tkPowerUpInstallerTitleGeneric = "power_up_installer_title_generic"
    tkPowerUpUpgradeTier = "power_up_upgrade_tier"
    tkPowerUpInstallerClose = "power_up_installer_close"
    tkPowerUpSelectUpgrade = "power_up_select_upgrade"
    tkPowerUpRolling = "power_up_rolling"
    tkPowerUpRerollOptions = "power_up_reroll_options"
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
    tkPowerupWallTurretsDesc = "powerup_wall_turrets_desc"
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
    tkPowerupCelestialVeil = "powerup_celestial_veil"
    tkPowerupCelestialVeilDesc = "powerup_celestial_veil_desc"
    
    # Player Feedback
    tkPlayerDodge = "player_dodge"
    tkPlayerParry = "player_parry"
    tkPlayerPhase = "player_phase"
    tkPlayerVeil = "player_veil"
    
    # System Messages
    tkSystemDefensiveProcesses = "system_defensive_processes"
    tkSystemPressAnyKey = "system_press_any_key"
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
    
    # Wave Celebration (d_enhancements)
    tkWaveClearedText = "wave_cleared_text"
    tkBossDefeatedText = "boss_defeated_text"
    tkWaveCelebKills = "wave_celeb_kills"
    tkWaveCelebAccuracy = "wave_celeb_accuracy"
    tkWaveCelebTime = "wave_celeb_time"
    tkWaveCelebCoins = "wave_celeb_coins"
    tkWaveCelebMaxCombo = "wave_celeb_max_combo"
    
    # Achievement popup (d_enhancements)
    tkAchievementUnlocked = "achievement_unlocked"
    
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
    
    # Milestone / micro-reward popups (d_systems)
    tkMilestoneAchievement = "milestone_achievement"
    tkMassacreBonus = "massacre_bonus"
    tkWaveStatsFlawless = "wave_stats_flawless"
    tkWaveStatsTitle = "wave_stats_title"
    tkWaveStatsKillsLabel = "wave_stats_kills_label"
    tkWaveStatsTimeLabel = "wave_stats_time_label"
    
    # Milestone names & descriptions (d_systems)
    tkMilestoneFirstBossName = "milestone_first_boss_name"
    tkMilestoneFirstBossDesc = "milestone_first_boss_desc"
    tkMilestoneVeteranName = "milestone_veteran_name"
    tkMilestoneVeteranDesc = "milestone_veteran_desc"
    tkMilestoneEliteName = "milestone_elite_name"
    tkMilestoneEliteDesc = "milestone_elite_desc"
    tkMilestoneCenturionName = "milestone_centurion_name"
    tkMilestoneCenturionDesc = "milestone_centurion_desc"
    tkMilestoneExecutionerName = "milestone_executioner_name"
    tkMilestoneExecutionerDesc = "milestone_executioner_desc"
    tkMilestoneDeathName = "milestone_death_name"
    tkMilestoneDeathDesc = "milestone_death_desc"
    tkMilestoneWealthyName = "milestone_wealthy_name"
    tkMilestoneWealthyDesc = "milestone_wealthy_desc"
    tkMilestoneTycoonName = "milestone_tycoon_name"
    tkMilestoneTycoonDesc = "milestone_tycoon_desc"
    
    # 3D Boss Game HUD (game3d/game_3d.nim)
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
    
    # Settings
    "settings_title": "SETTINGS",
    "settings_fps_limit": "FPS Limit:",
    "settings_click_edit": "Click to edit, Enter to confirm",
    "settings_sound_effects": "Sound Effects:",
    "settings_music": "Music:",
    "settings_fullscreen": "Fullscreen:",
    "settings_fullscreen_toggle": "(Press F11 to toggle)",
    "settings_show_fps": "Show FPS:",
    "settings_mouse_support": "Mouse Support:",
    "settings_mouse_support_desc": "(new menu navigation)",
    "settings_show_cursor": "Show Cursor:",
    "settings_show_cursor_desc": "(visual only)",
    "settings_debug_panel": "Debug Panel:",
    "settings_debug_panel_desc": "(top-right stats)",
    "settings_show_hints": "Show Hints:",
    "settings_show_hints_desc": "(E: Wall, ESC: Pause)",
    "settings_show_enemy_labels": "Show Enemy Labels:",
    "settings_show_enemy_labels_desc": "(name tags above enemies)",
    "settings_language": "Language:",
    "settings_back_to_menu": "Press ESC to return to menu",
    
    # Settings window tabs and sections
    "settings_tab_graphics": "Graphics",
    "settings_tab_audio": "Audio",
    "settings_tab_controls": "Controls",
    "settings_tab_gameplay": "Gameplay",
    
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
    "shop_damage_plus": "Damage +",
    "shop_damage_plus_desc": "Increase bullet damage",
    "shop_fire_rate_plus": "Fire Rate +",
    "shop_fire_rate_plus_desc": "Shoot faster",
    "shop_move_speed_plus": "Move Speed +",
    "shop_move_speed_plus_desc": "Move faster",
    "shop_max_health_plus": "Max Health +",
    "shop_max_health_plus_desc": "Increase max HP",
    "shop_bullet_speed_plus": "Bullet Speed +",
    "shop_bullet_speed_plus_desc": "Faster bullets",
    "shop_wall_x4": "Wall (x4)",
    "shop_wall_x4_desc": "Buy 4 deployable walls",
    
    # Powerup Names
    "powerup_double_shot": "Double Shot",
    "powerup_rotating_shield": "Rotating Shield",
    "powerup_magical_bullets": "Magical Bullets",
    "powerup_piercing_shots": "Piercing Shots",
    "powerup_multi_shot": "Multi-Shot",
    "powerup_explosive_bullets": "Explosive Rounds",
    "powerup_life_steal": "Life Steal",
    "powerup_rapid_fire": "Rapid Fire",
    "powerup_max_health": "Vitality",
    "powerup_speed_boost": "Agility",
    "powerup_bullet_speed": "Velocity",
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
    "powerup_celestial_veil": "Celestial Veil",
    
    # Powerup Descriptions
    "powerup_double_shot_desc": "Fire additional burst after 0.08s (-15% dmg per bullet, -25% fire rate)",
    "powerup_rotating_shield_desc1": "3 shields (30% coverage, 300 HP, 5.5s respawn)",
    "powerup_rotating_shield_desc2": "3 shields (35% coverage, 400 HP, 4.5s respawn)",
    "powerup_rotating_shield_desc3": "3 shields (40% coverage, 500 HP, 3.75s respawn)",
    "powerup_magical_bullets_desc": "Bullets track nearest enemy",
    "powerup_piercing_shots_desc1": "Bullets pierce 1 enemy (-33% damage per pierce)",
    "powerup_piercing_shots_desc2": "Bullets pierce 2 enemies (-33% damage per pierce)",
    "powerup_piercing_shots_desc3": "Bullets pierce 3 enemies (-33% damage per pierce)",
    "powerup_multi_shot_desc": "Shoot in 3 directions",
    "powerup_explosive_bullets_desc1": "Bullets explode (50% bullet dmg, small radius)",
    "powerup_explosive_bullets_desc2": "Bullets explode (50% bullet dmg, medium radius)",
    "powerup_explosive_bullets_desc3": "Bullets explode (50% bullet dmg, large radius)",
    "powerup_life_steal_desc1": "Heal 50 HP per 12 kills",
    "powerup_life_steal_desc2": "Heal 50 HP per 9 kills",
    "powerup_life_steal_desc3": "Heal 50 HP per 6 kills",
    "powerup_rapid_fire_desc": "+40% fire rate",
    "powerup_max_health_desc": "+1450 max HP",
    "powerup_speed_boost_desc": "+40% movement speed",
    "powerup_bullet_speed_desc": "+40% bullet speed",
    "powerup_lucky_coins_desc": "Doubles all coins collected",
    "powerup_wall_master_desc": "Walls have +250% HP turrets have +100% damage",
    "powerup_regeneration_desc1": "Regen 150-250 HP per wave",
    "powerup_regeneration_desc2": "Regen 250-450 HP per wave",
    "powerup_regeneration_desc3": "Regen 350-650 HP per wave",
    "powerup_dodge_chance_desc1": "15% chance to dodge hits",
    "powerup_dodge_chance_desc2": "20% chance to dodge hits",
    "powerup_dodge_chance_desc3": "30% chance to dodge hits",
    "powerup_critical_hit_desc1": "20% chance for 2x damage (all sources)",
    "powerup_critical_hit_desc2": "35% chance for 2x damage (all sources)",
    "powerup_critical_hit_desc3": "50% chance for 2x damage (all sources)",
    "powerup_blood_bullets_desc1": "Heal 1.75% of bullet damage (blood element)",
    "powerup_blood_bullets_desc2": "Heal 2.25% of bullet damage (blood element)",
    "powerup_blood_bullets_desc3": "Heal 3% of bullet damage (blood element)",
    "powerup_bullet_ricochet_desc1": "Bullets ricochet once (75% damage per ricochet)",
    "powerup_bullet_ricochet_desc2": "Bullets ricochet twice (75% damage per ricochet)",
    "powerup_bullet_ricochet_desc3": "Bullets ricochet 3 times (75% damage per ricochet)",
    "powerup_slow_field_desc1": "Slow enemies 30% in 150 radius",
    "powerup_slow_field_desc2": "Slow enemies 45% in 200 radius",
    "powerup_slow_field_desc3": "Slow enemies 55% in 250 radius",
    "powerup_rage_desc1": "+5% dmg per 10% HP lost",
    "powerup_rage_desc2": "+8% dmg per 10% HP lost",
    "powerup_rage_desc3": "+12% dmg per 10% HP lost",
    "powerup_berserker_desc1": "+5% fire rate per 10% HP lost",
    "powerup_berserker_desc2": "+8% fire rate per 10% HP lost",
    "powerup_berserker_desc3": "+12% fire rate per 10% HP lost",
    "powerup_thorns_desc1": "Reflect 50% damage to attacker",
    "powerup_thorns_desc2": "Reflect 100% damage to attacker",
    "powerup_thorns_desc3": "Reflect 200% damage to attacker",
    "powerup_bullet_split_desc1": "Bullets split into 2 on hit",
    "powerup_bullet_split_desc2": "Bullets split into 3 on hit",
    "powerup_bullet_split_desc3": "Bullets split into 4 on hit",
    "powerup_chain_lightning_desc1": "Hit chains to 1 enemy (70% bullet dmg, 120 range, 0.05s stun)",
    "powerup_chain_lightning_desc2": "Hit chains to 2 enemies (85% bullet dmg, 140 range, 0.05s stun)",
    "powerup_chain_lightning_desc3": "Hit chains to 3 enemies (100% bullet dmg, 160 range, 0.05s stun)",
    "powerup_frost_shots_desc1": "Bullets slow enemies 25% (permanent)",
    "powerup_frost_shots_desc2": "Bullets slow enemies 40% (permanent)",
    "powerup_frost_shots_desc3": "Bullets slow enemies 60% (permanent)",
    "powerup_poison_shot_desc1": "Bullets poison ({0} dmg/s, 4s)",
    "powerup_poison_shot_desc2": "Bullets poison ({0} dmg/s, 5s)",
    "powerup_poison_shot_desc3": "Bullets poison ({0} dmg/s, 6s)",
    "powerup_fire_bullets_desc1": "Bullets burn ({0} dmg/s, 2s)",
    "powerup_fire_bullets_desc2": "Bullets burn ({0} dmg/s, 3s)",
    "powerup_fire_bullets_desc3": "Bullets burn ({0} dmg/s, 4s)",
    "powerup_wind_bullets_desc1": "Bullets knock back enemies (weak push)",
    "powerup_wind_bullets_desc2": "Bullets knock back enemies (medium push)",
    "powerup_wind_bullets_desc3": "Bullets knock back enemies (strong push)",
    "powerup_fire_aura_desc1": "Burn enemies {0} dmg/s in 150 radius (2s)",
    "powerup_fire_aura_desc2": "Burn enemies {0} dmg/s in 200 radius (3s)",
    "powerup_fire_aura_desc3": "Burn enemies {0} dmg/s in 250 radius (4s)",
    "powerup_lightning_aura_desc1": "Zap {0} dmg/s in 150 radius (chains 1x)",
    "powerup_lightning_aura_desc2": "Zap {0} dmg/s in 200 radius (chains 2x)",
    "powerup_lightning_aura_desc3": "Zap {0} dmg/s in 250 radius (chains 3x)",
    "powerup_poison_aura_desc1": "Poison {0} dmg/s in 150 radius (6s duration)",
    "powerup_poison_aura_desc2": "Poison {0} dmg/s in 200 radius (8s duration)",
    "powerup_poison_aura_desc3": "Poison {0} dmg/s in 250 radius (10s duration)",
    "powerup_wind_aura_desc1": "Push enemies away in 150 radius (weak)",
    "powerup_wind_aura_desc2": "Push enemies away in 200 radius (medium)",
    "powerup_wind_aura_desc3": "Push enemies away in 250 radius (strong)",
    "powerup_time_warp_desc": "Slow time 50% for 3.5s (2 uses/wave, 10s cd)",
    "powerup_gravity_well_desc": "Pull enemies in 300 radius",
    "powerup_phase_shift_desc": "Dash forward (5s cd, 0.5s invuln, scales with speed)",
    "powerup_overcharge_desc": "+10% dmg per 100 units traveled (max 150%, reaches at 1000 units)",
    "powerup_echo_shots_desc": "Bullets leave ghost trail (60% dmg)",
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
    "powerup_arcane_bullets_desc1": "Bullets enhanced with arcane power (+40% bullet damage, arcane)",
    "powerup_arcane_bullets_desc2": "Bullets enhanced with arcane power (+80% bullet damage, arcane)",
    "powerup_arcane_bullets_desc3": "Bullets enhanced with arcane power (+120% bullet damage, arcane)",
    "powerup_arcane_aura_desc1": "Arcane aura {0} dmg/s in 150 radius, arcane",
    "powerup_arcane_aura_desc2": "Arcane aura {0} dmg/s in 200 radius, arcane",
    "powerup_arcane_aura_desc3": "Arcane aura {0} dmg/s in 250 radius, arcane",
    "powerup_fire_mastery_desc": "Fire effects: +150% dmg, +100% duration, +35% slow",
    "powerup_poison_mastery_desc": "Poison effects: +150% dmg, +100% duration, +30% slow",
    "powerup_frost_mastery_desc": "Frost effects: +150% dmg, +100% duration, +20% slow",
    "powerup_arcane_mastery_desc": "Arcane effects: +100% dmg, piercing",
    "powerup_lightning_mastery_desc": "Lightning effects: +150% dmg, +25% slow, +1 chain, +50% range",
    "powerup_wind_mastery_desc": "Wind effects: +150% dmg, +40% slow, stronger push",
    "powerup_parry_desc": "Active: Invincible for 0.5s, bounce enemy bullets (5s cooldown)",
    "powerup_blood_orb_desc1": "4 blood orbs ({0} dmg/hit, 1.75% lifesteal)",
    "powerup_blood_orb_desc2": "8 blood orbs ({0} dmg/hit, 2.25% lifesteal)",
    "powerup_blood_orb_desc3": "12 blood orbs ({0} dmg/hit, 3% lifesteal)",
    "powerup_blood_aura_desc1": "Blood aura {0} dmg/s in 150 radius, heal 2.5% dealt",
    "powerup_blood_aura_desc2": "Blood aura {0} dmg/s in 200 radius, heal 5% dealt",
    "powerup_blood_aura_desc3": "Blood aura {0} dmg/s in 250 radius, heal 10% dealt",
    "powerup_blood_mastery_desc": "Blood effects: +150% dmg, +100% lifesteal",
    "powerup_radial_burst_desc1": "Fire 8 bullets in a circle every 3.5s (uses player damage)",
    "powerup_radial_burst_desc2": "Fire 10 bullets in a circle every 3.0s (uses player damage)",
    "powerup_radial_burst_desc3": "Fire 14 bullets in a circle every 2.0s (uses player damage)",
    "powerup_wall_turrets_desc": "Walls shoot enemies (100 + {0} (15%) dmg, 1.5s cooldown)",
    "powerup_pulse_armor_desc1": "Taking damage pushes nearby enemies back (no dmg, +1% maxHP scaling)",
    "powerup_pulse_armor_desc2": "Shockwave pushes further and deals 200 + 1% maxHP damage",
    "powerup_pulse_armor_desc3": "Shockwave pushes even further and deals 400 + 1% maxHP damage",
    "powerup_heavy_rounds_desc1": "Bullets 15% larger with slight knockback",
    "powerup_heavy_rounds_desc2": "Bullets 25% larger with increased knockback",
    "powerup_heavy_rounds_desc3": "Bullets 35% larger with strong knockback",
    "powerup_fortified_desc1": "Reduce damage taken by 15% and gain 400 max HP",
    "powerup_fortified_desc2": "Reduce damage taken by 25% and gain 800 (+400) max HP",
    "powerup_fortified_desc3": "Reduce damage taken by 35% and gain 1200 (+400) max HP",
    "powerup_special_rounds_desc1": "Every 5th bullet deals +75% bonus damage",
    "powerup_special_rounds_desc2": "Every 4th bullet deals +75% bonus damage",
    "powerup_special_rounds_desc3": "Every 3rd bullet deals +75% bonus damage",
    "powerup_giant_slayer_desc1": "Deal 1% of enemy current HP as bonus damage",
    "powerup_giant_slayer_desc2": "Deal 1.75% of enemy current HP as bonus damage",
    "powerup_giant_slayer_desc3": "Deal 2.5% of enemy current HP as bonus damage",
    "powerup_celestial_veil_desc": "Absorb 1 hit per wave — resets at the start of each wave",
    
    # Player Feedback
    "player_dodge": "DODGE!",
    "player_parry": "PARRY!",
    "player_phase": "PHASE SHIFT!",
    "player_veil": "VEIL!",
    
    # System Messages
    "system_defensive_processes": "All defensive processes have been terminated.",
    "system_press_any_key": "Press almost any key to continue...",
    "system_no_statistics": "No statistics available",
    "system_press_esc_to_return": "Press ESC to return",
    
    # Loading Screen
    "loading_title": "TopHat-ShooterOS",
    "loading_subtitle": "v5.3 Edition",
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
    "os_system_paused": "System paused - press SPACE to continue",
    "os_press_space_continue": "Press SPACE to continue",
    
    # OS Desktop / System Info
    "os_system_monitor": "System Monitor",
    "os_cpu_idle": "CPU: Idle",
    "os_memory": "Memory: 2.4 / 16 GB",
    "os_network": "Network: Connected",
    "os_tophat_os": "TopHat-ShooterOS",
    "os_edition": "[v5.3 Edition]",
    "os_tophat_button": "TopHat",
    "os_net_indicator": "NET",
    
    # Stats Labels
    "stats_system_analytics": "System Analytics",
    "stats_run_report": "Run Report",
    "stats_wave_label": "Wave",
    "stats_time_label": "TIME",
    "stats_kills_label": "KILLS",
    "stats_accuracy_label": "ACCURACY",
    "stats_avg_dps": "AVG DPS",
    "stats_max_combo": "Max Combo",
    "stats_avg_combo": "Avg Combo",
    "stats_perfect_waves": "Perfect Waves",
    "stats_play_style_aggressive": "Aggressive",
    "stats_play_style_defensive": "Defensive",
    "stats_play_style_mobile": "Mobile",
    "stats_play_style_tank": "Tank",
    "stats_play_style_balanced": "Balanced",
    "stats_no_power_ups_selected": "No power-ups selected",
    "stats_no_graph_data_short": "No graph data",
    "stats_controls_footer": "[ENTER] Continue  |  [ESC] Close",
    "stats_wave_mode": "Wave Mode",
    "stats_time_survival_mode": "Time Survival",
    "stats_sandbox_mode": "Sandbox",
    "stats_pvp_mode": "PvP",
    "stats_bar_wave_max": "[WAVE] Max Reached",
    "stats_bar_kill_best": "[KILL] Best Performance",
    "stats_bar_boss_eliminated": "[BOSS] Eliminated",
    "stats_bar_time_survival": "[TIME] Longest Survival",
    "stats_combat_label": "COMBAT",
    "stats_movement_label": "MOVEMENT & SURVIVAL",
    "stats_performance_label": "PERFORMANCE",
    "stats_resources_label": "RESOURCES",
    "stats_play_style_label": "PLAY STYLE",
    "stats_dps_over_time_label": "DPS OVER TIME",
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
    
    # Achievement popup
    "achievement_unlocked": "ACHIEVEMENT UNLOCKED!",
    
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
    
    # Milestone / micro-reward popups
    "milestone_achievement": "Achievement:",
    "massacre_bonus": "MASSACRE BONUS!",
    "wave_stats_flawless": "FLAWLESS!",
    "wave_stats_title": "WAVE",
    "wave_stats_kills_label": "Kills:",
    "wave_stats_time_label": "Time:",
    
    # Milestone names & descriptions
    "milestone_first_boss_name": "FIRST BOSS DEFEATED",
    "milestone_first_boss_desc": "Survived your first boss encounter",
    "milestone_veteran_name": "VETERAN SURVIVOR",
    "milestone_veteran_desc": "Reached wave 10",
    "milestone_elite_name": "ELITE PLAYER",
    "milestone_elite_desc": "Reached wave 25",
    "milestone_centurion_name": "CENTURION",
    "milestone_centurion_desc": "Eliminated 100 enemies",
    "milestone_executioner_name": "EXECUTIONER",
    "milestone_executioner_desc": "Eliminated 500 enemies",
    "milestone_death_name": "DEATH INCARNATE",
    "milestone_death_desc": "Eliminated 1000 enemies",
    "milestone_wealthy_name": "WEALTHY",
    "milestone_wealthy_desc": "Collected 1000 lifetime coins",
    "milestone_tycoon_name": "TYCOON",
    "milestone_tycoon_desc": "Collected 5000 lifetime coins",
    
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
    "stats_time_at_low_hp": "Time at Low HP",
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
    "stats_play_style_aggressive": "Aggressive",
    "stats_play_style_defensive": "Defensive",
    "stats_play_style_mobile": "Mobile",
    "stats_play_style_tank": "Tank",
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
    "game_over_continue": "> CONTINUE",
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
    
    # HUD/Notifications
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
    "shop_tab_particles": "PARTICLES",
    "shop_scroll_hint": "Scroll with mouse wheel to see all skins",
    "shop_click_equip": "Click to equip",
    "shop_window_title": "Customization Shop",
    "shop_equipped": "[EQUIPPED]",
    "shop_currently_equipped": "Currently Equipped:",
    "shop_customize_appearance": "CUSTOMIZE YOUR APPEARANCE",
    "shop_customize_bullets": "CUSTOMIZE YOUR BULLETS",
    "shop_choose_shape": "CHOOSE YOUR SHAPE",
    "shop_customize_effects": "CUSTOMIZE SHOOTING EFFECTS",
    
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
    
    # Legendary Panel
    "legendary_panel_title": "LEGENDARY",
    "legendary_chronos": "Chronos",
    "legendary_phase": "Phase",
    "legendary_parry": "Parry",
    "legendary_active": "ACTIVE",
    "legendary_ready": "Ready",
    "legendary_dashing": "DASHING",
    
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
    "help_enemies_topic": "ENEMY TYPES",
    "help_bosses_topic": "BOSS INFORMATION",
    "help_shop_topic": "SHOP ITEMS",
    "help_clear_command": "Clear the screen",
    "help_command_separator": "--------------------------------------",
    "help_launch_topics": "play/survival/sandbox/stats/settings/quit",
    "help_opening_settings": "Opening Settings.exe...",
    "help_launching_sandbox": "Launching Sandbox.exe...",
    "help_shutting_down": "Shutting down...",
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
    "help_wind_aura": "Wind Aura - Pushes enemies away",
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
    
    # Help System - Shop items
    "help_shop_damage_plus": "Damage + (8 CR base)",
    "help_shop_damage_plus_desc": "Increase bullet damage",
    "help_shop_fire_rate_plus": "Fire Rate + (10 CR base)",
    "help_shop_fire_rate_plus_desc": "Shoot faster",
    "help_shop_move_speed_plus": "Move Speed + (7 CR base)",
    "help_shop_move_speed_plus_desc": "Move faster",
    "help_shop_max_health_plus": "Max Health + (10 CR base)",
    "help_shop_max_health_plus_desc": "Increase maximum HP",
    "help_shop_bullet_speed_plus": "Bullet Speed + (6 CR base)",
    "help_shop_bullet_speed_plus_desc": "Faster bullet velocity",
    "help_shop_wall_x4": "Wall x4 (14 CR base)",
    "help_shop_wall_x4_desc": "Buy 4 deployable walls",
    
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
    "help_cost_scaling_formula": "- Costs increase with each purchase\n  - Each buy: cost = baseCost * 1.45^bought",
    "help_kill_enemies_to_collect": "- Kill enemies to collect coins",
    "help_elite_drop_more": "- Elite enemies drop more coins",
    "help_boss_drop_large": "- Bosses drop large amounts",
    "help_opens_after_powerup": "- Opens after power-up selection",
    "help_available_between_waves": "- Available between waves",
    
    # Game Notifications and UI
    "game_wave_announcement_main": "*** WAVE ***",
    "game_instructions_wall": "E: Wall | ESC: Pause",
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
    
    # Power-up Installer
    "power_up_installer_title": "LEGENDARY UPGRADE INSTALLER",
    "power_up_installer_title_generic": "PROCESS UPGRADE MANAGER",
    "power_up_upgrade_tier": "UPGRADE TIER:",
    "power_up_installer_close": "X",
    "power_up_select_upgrade": "v SELECT UPGRADE TO INSTALL:",
    "power_up_rolling": "[!] ROLLING...",
    "power_up_reroll_options": "[R] Reroll Options",
    
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
    
    "stats_play_style_aggressive": "Aggressive",
    "stats_play_style_defensive": "Defensive",
    "stats_play_style_mobile": "Mobile",
    "stats_play_style_tank": "Tank",
    "stats_no_powerups_selected": "No power-ups selected",
    "stats_dps_over_time_label": "DPS OVER TIME",
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
    "boss_12_desc": "The ultimate challenge - combines all previous boss mechanics"
  }.toTable,
  
  Spanish: {
    # Main Menu
    "menu_play": "jugar",
    "menu_survival": "survival",
    "menu_stats": "stats",
    "menu_help": "ayuda",
    "menu_settings": "config",
    "menu_quit": "salir",
    "menu_sandbox": "sandbox",
    
    # Settings
    "settings_title": "CONFIG",
    "settings_fps_limit": "Límite FPS:",
    "settings_click_edit": "Clic: editar, Enter: confirmar",
    "settings_sound_effects": "Efectos:",
    "settings_music": "Música:",
    "settings_fullscreen": "Pantalla:",
    "settings_fullscreen_toggle": "(F11 para cambiar)",
    "settings_show_fps": "Mostrar FPS:",
    "settings_mouse_support": "Ratón:",
    "settings_mouse_support_desc": "(navegación de menú)",
    "settings_show_cursor": "Cursor:",
    "settings_show_cursor_desc": "(solo visual)",
    "settings_debug_panel": "Debug:",
    "settings_debug_panel_desc": "(stats arriba-derecha)",
    "settings_show_hints": "Consejos:",
    "settings_show_hints_desc": "(E: Muro, ESC: Pausa)",
    "settings_show_enemy_labels": "Etiquetas:",
    "settings_show_enemy_labels_desc": "(nombres sobre enemigos)",
    "settings_language": "Idioma:",
    "settings_back_to_menu": "ESC para volver",
    
    # Settings window tabs and sections
    "settings_tab_graphics": "Gráficos",
    "settings_tab_audio": "Audio",
    "settings_tab_controls": "Controles",
    "settings_tab_gameplay": "Juego",
    
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
    "shop_owned": "Poseído",
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
    "shop_damage_plus": "Daño +",
    "shop_damage_plus_desc": "Aumentar daño de balas",
    "shop_fire_rate_plus": "Cadencia +",
    "shop_fire_rate_plus_desc": "Disparar más rápido",
    "shop_move_speed_plus": "Velocidad +",
    "shop_move_speed_plus_desc": "Moverse más rápido",
    "shop_max_health_plus": "Vida Máx +",
    "shop_max_health_plus_desc": "Aumentar HP máximo",
    "shop_bullet_speed_plus": "Vel. Balas +",
    "shop_bullet_speed_plus_desc": "Balas más rápidas",
    "shop_wall_x4": "Muro (x4)",
    "shop_wall_x4_desc": "Comprar 4 muros desplegables",
    
    # Powerup Names
    "powerup_double_shot": "Disparo Doble",
    "powerup_rotating_shield": "Escudo Giratorio",
    "powerup_magical_bullets": "Balas Mágicas",
    "powerup_piercing_shots": "Disparos Perforantes",
    "powerup_multi_shot": "Multidisparo",
    "powerup_explosive_bullets": "Balas Explosivas",
    "powerup_life_steal": "Robo de Vida",
    "powerup_rapid_fire": "Fuego Rápido",
    "powerup_max_health": "Vitalidad",
    "powerup_speed_boost": "Agilidad",
    "powerup_bullet_speed": "Velocidad",
    "powerup_lucky_coins": "Codicia",
    "powerup_wall_master": "Fortificar",
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
    "powerup_phase_shift": "Caminante Fase",
    "powerup_overcharge": "Sobrecarga",
    "powerup_echo_shots": "Golpe de Eco",
    "powerup_rotating_orbs": "Orbes Elementales",
    "powerup_poison_orb": "Orbes Venenosos",
    "powerup_fire_orb": "Orbes de Fuego",
    "powerup_lightning_orb": "Orbes de Rayo",
    "powerup_wind_orb": "Orbes de Viento",
    "powerup_frost_orb": "Orbes Helados",
    "powerup_arcane_bullets": "Balas Arcanas",
    "powerup_arcane_aura": "Aura Arcana",
    "powerup_arcane_orb": "Orbes Arcanos",
    "powerup_fire_mastery": "Maestría Infernal",
    "powerup_poison_mastery": "Señor Tóxico",
    "powerup_frost_mastery": "Rey de Hielo",
    "powerup_arcane_mastery": "Ascensión Arcana",
    "powerup_lightning_mastery": "Señor de Tormentas",
    "powerup_wind_mastery": "Maestro del Viento",
    "powerup_parry": "Parry",
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
    "powerup_celestial_veil": "Velo Celestial",
    
    # Powerup Descriptions
    "powerup_double_shot_desc": "Disparar ráfaga adicional después de 0.08s (-15% daño por bala, -25% cadencia)",
    "powerup_rotating_shield_desc1": "3 escudos (30% cobertura, 300 HP, 5.5s reaparición)",
    "powerup_rotating_shield_desc2": "3 escudos (35% cobertura, 400 HP, 4.5s reaparición)",
    "powerup_rotating_shield_desc3": "3 escudos (40% cobertura, 500 HP, 3.75s reaparición)",
    "powerup_magical_bullets_desc": "Las balas rastrean al enemigo más cercano",
    "powerup_piercing_shots_desc1": "Balas perforan 1 enemigo (-33% daño por perforación)",
    "powerup_piercing_shots_desc2": "Balas perforan 2 enemigos (-33% daño por perforación)",
    "powerup_piercing_shots_desc3": "Balas perforan 3 enemigos (-33% daño por perforación)",
    "powerup_multi_shot_desc": "Disparar en 3 direcciones",
    "powerup_explosive_bullets_desc1": "Balas explotan (50% daño bala, radio pequeño)",
    "powerup_explosive_bullets_desc2": "Balas explotan (50% daño bala, radio mediano)",
    "powerup_explosive_bullets_desc3": "Balas explotan (50% daño bala, radio grande)",
    "powerup_life_steal_desc1": "Curar 100 HP cada 20 muertes",
    "powerup_life_steal_desc2": "Curar 100 HP cada 15 muertes",
    "powerup_life_steal_desc3": "Curar 100 HP cada 10 muertes",
    "powerup_rapid_fire_desc": "+40% cadencia de fuego",
    "powerup_max_health_desc": "+1450 HP máximo",
    "powerup_speed_boost_desc": "+40% velocidad movimiento",
    "powerup_bullet_speed_desc": "+40% velocidad de balas",
    "powerup_lucky_coins_desc": "Duplica todas las monedas recogidas",
    "powerup_wall_master_desc": "Muros tienen +250% HP torretas +100% daño",
    "powerup_regeneration_desc1": "Regen 150-250 HP por oleada",
    "powerup_regeneration_desc2": "Regen 250-450 HP por oleada",
    "powerup_regeneration_desc3": "Regen 350-650 HP por oleada",
    "powerup_dodge_chance_desc1": "15% probabilidad esquivar golpes",
    "powerup_dodge_chance_desc2": "20% probabilidad esquivar golpes",
    "powerup_dodge_chance_desc3": "30% probabilidad esquivar golpes",
    "powerup_critical_hit_desc1": "20% probabilidad de 2x daño (todas fuentes)",
    "powerup_critical_hit_desc2": "35% probabilidad de 2x daño (todas fuentes)",
    "powerup_critical_hit_desc3": "50% probabilidad de 2x daño (todas fuentes)",
    "powerup_blood_bullets_desc1": "Curar 1.75% del daño de bala (elemento sangre)",
    "powerup_blood_bullets_desc2": "Curar 2.25% del daño de bala (elemento sangre)",
    "powerup_blood_bullets_desc3": "Curar 3% del daño de bala (elemento sangre)",
    "powerup_bullet_ricochet_desc1": "Balas rebotan 1 vez (75% daño por rebote)",
    "powerup_bullet_ricochet_desc2": "Balas rebotan 2 veces (75% daño por rebote)",
    "powerup_bullet_ricochet_desc3": "Balas rebotan 3 veces (75% daño por rebote)",
    "powerup_slow_field_desc1": "Ralentizar enemigos 30% en radio 120",
    "powerup_slow_field_desc2": "Ralentizar enemigos 45% en radio 160",
    "powerup_slow_field_desc3": "Ralentizar enemigos 55% en radio 200",
    "powerup_rage_desc1": "+5% daño por 10% HP perdido",
    "powerup_rage_desc2": "+8% daño por 10% HP perdido",
    "powerup_rage_desc3": "+12% daño por 10% HP perdido",
    "powerup_berserker_desc1": "+5% cadencia por 10% HP perdido",
    "powerup_berserker_desc2": "+8% cadencia por 10% HP perdido",
    "powerup_berserker_desc3": "+12% cadencia por 10% HP perdido",
    "powerup_thorns_desc1": "Reflejar 50% daño al atacante",
    "powerup_thorns_desc2": "Reflejar 100% daño al atacante",
    "powerup_thorns_desc3": "Reflejar 200% daño al atacante",
    "powerup_bullet_split_desc1": "Balas se dividen en 2 al impactar",
    "powerup_bullet_split_desc2": "Balas se dividen en 3 al impactar",
    "powerup_bullet_split_desc3": "Balas se dividen en 4 al impactar",
    "powerup_chain_lightning_desc1": "Golpe encadena a 1 enemigo (70% daño bala, rango 120, aturdimiento 0.05s)",
    "powerup_chain_lightning_desc2": "Golpe encadena a 2 enemigos (85% daño bala, rango 140, aturdimiento 0.05s)",
    "powerup_chain_lightning_desc3": "Golpe encadena a 3 enemigos (100% daño bala, rango 160, aturdimiento 0.05s)",
    "powerup_frost_shots_desc1": "Balas ralentizan enemigos 25% (permanente)",
    "powerup_frost_shots_desc2": "Balas ralentizan enemigos 40% (permanente)",
    "powerup_frost_shots_desc3": "Balas ralentizan enemigos 60% (permanente)",
    "powerup_poison_shot_desc1": "Balas envenenan ({0} daño/s, 4s)",
    "powerup_poison_shot_desc2": "Balas envenenan ({0} daño/s, 5s)",
    "powerup_poison_shot_desc3": "Balas envenenan ({0} daño/s, 6s)",
    "powerup_fire_bullets_desc1": "Balas queman ({0} daño/s, 2s)",
    "powerup_fire_bullets_desc2": "Balas queman ({0} daño/s, 3s)",
    "powerup_fire_bullets_desc3": "Balas queman ({0} daño/s, 4s)",
    "powerup_wind_bullets_desc1": "Balas empujan enemigos (empuje débil)",
    "powerup_wind_bullets_desc2": "Balas empujan enemigos (empuje medio)",
    "powerup_wind_bullets_desc3": "Balas empujan enemigos (empuje fuerte)",
    "powerup_fire_aura_desc1": "Quemar enemigos {0} daño/s en radio 120 (2s)",
    "powerup_fire_aura_desc2": "Quemar enemigos {0} daño/s en radio 160 (3s)",
    "powerup_fire_aura_desc3": "Quemar enemigos {0} daño/s en radio 200 (4s)",
    "powerup_lightning_aura_desc1": "Electrocutar {0} daño/s en radio 120 (encadena 1x)",
    "powerup_lightning_aura_desc2": "Electrocutar {0} daño/s en radio 160 (encadena 2x)",
    "powerup_lightning_aura_desc3": "Electrocutar {0} daño/s en radio 200 (encadena 3x)",
    "powerup_poison_aura_desc1": "Veneno {0} daño/s en radio 120 (duración 6s)",
    "powerup_poison_aura_desc2": "Veneno {0} daño/s en radio 160 (duración 8s)",
    "powerup_poison_aura_desc3": "Veneno {0} daño/s en radio 200 (duración 10s)",
    "powerup_wind_aura_desc1": "Empujar enemigos en radio 120 (débil)",
    "powerup_wind_aura_desc2": "Empujar enemigos en radio 160 (medio)",
    "powerup_wind_aura_desc3": "Empujar enemigos en radio 200 (fuerte)",
    "powerup_time_warp_desc": "Ralentizar tiempo 50% por 3.5s (2 usos/oleada, 10s cd)",
    "powerup_gravity_well_desc": "Atraer enemigos en radio 300",
    "powerup_phase_shift_desc": "Dash adelante (5s cd, 0.5s invuln, escala con velocidad)",
    "powerup_overcharge_desc": "+10% daño por 100 unidades recorridas (max 150%, alcanza a 1000 unidades)",
    "powerup_echo_shots_desc": "Balas dejan rastro fantasma (60% daño)",
    "powerup_rotating_orbs_desc": "Los 6 orbes elementales ({0} daño/golpe)",
    "powerup_poison_orb_desc1": "4 orbes veneno ({0} daño/golpe)",
    "powerup_poison_orb_desc2": "8 orbes veneno ({0} daño/golpe)",
    "powerup_poison_orb_desc3": "12 orbes veneno ({0} daño/golpe)",
    "powerup_fire_orb_desc1": "4 orbes fuego ({0} daño/golpe)",
    "powerup_fire_orb_desc2": "8 orbes fuego ({0} daño/golpe)",
    "powerup_fire_orb_desc3": "12 orbes fuego ({0} daño/golpe)",
    "powerup_lightning_orb_desc1": "4 orbes rayo ({0} daño/golpe)",
    "powerup_lightning_orb_desc2": "8 orbes rayo ({0} daño/golpe)",
    "powerup_lightning_orb_desc3": "12 orbes rayo ({0} daño/golpe)",
    "powerup_wind_orb_desc1": "4 orbes viento que empujan enemigos ({0} daño/golpe)",
    "powerup_wind_orb_desc2": "8 orbes viento que empujan enemigos ({0} daño/golpe)",
    "powerup_wind_orb_desc3": "12 orbes viento que empujan enemigos ({0} daño/golpe)",
    "powerup_frost_orb_desc1": "4 orbes hielo que ralentizan enemigos ({0} daño/golpe)",
    "powerup_frost_orb_desc2": "8 orbes hielo que ralentizan enemigos ({0} daño/golpe)",
    "powerup_frost_orb_desc3": "12 orbes hielo que ralentizan enemigos ({0} daño/golpe)",
    "powerup_arcane_orb_desc1": "4 orbes arcanos ({0} daño/golpe)",
    "powerup_arcane_orb_desc2": "8 orbes arcanos ({0} daño/golpe)",
    "powerup_arcane_orb_desc3": "12 orbes arcanos ({0} daño/golpe)",
    "powerup_arcane_bullets_desc1": "Balas mejoradas con poder arcano (+40% daño bala, arcano)",
    "powerup_arcane_bullets_desc2": "Balas mejoradas con poder arcano (+80% daño bala, arcano)",
    "powerup_arcane_bullets_desc3": "Balas mejoradas con poder arcano (+120% daño bala, arcano)",
    "powerup_arcane_aura_desc1": "Aura arcana {0} daño/s en radio 120, arcano",
    "powerup_arcane_aura_desc2": "Aura arcana {0} daño/s en radio 160, arcano",
    "powerup_arcane_aura_desc3": "Aura arcana {0} daño/s en radio 200, arcano",
    "powerup_fire_mastery_desc": "Efectos fuego: +150% daño, +100% duración, +35% ralentización",
    "powerup_poison_mastery_desc": "Efectos veneno: +150% daño, +100% duración, +30% ralentización",
    "powerup_frost_mastery_desc": "Efectos hielo: +150% daño, +100% duración, +20% ralentización",
    "powerup_arcane_mastery_desc": "Efectos arcanos: +100% daño, perforación",
    "powerup_lightning_mastery_desc": "Efectos rayo: +150% daño, +25% ralentización, +1 cadena, +50% rango",
    "powerup_wind_mastery_desc": "Efectos viento: +150% daño, +40% ralentización, empuje más fuerte",
    "powerup_parry_desc": "Activo: Invencible por 0.5s, rebota balas enemigas (5s enfriamiento)",
    "powerup_blood_orb_desc1": "4 orbes sangre ({0} daño/golpe, 1.75% robo vida)",
    "powerup_blood_orb_desc2": "8 orbes sangre ({0} daño/golpe, 2.25% robo vida)",
    "powerup_blood_orb_desc3": "12 orbes sangre ({0} daño/golpe, 3% robo vida)",
    "powerup_blood_aura_desc1": "Aura sangre {0} daño/s en radio 120, curar 2.5% infligido",
    "powerup_blood_aura_desc2": "Aura sangre {0} daño/s en radio 160, curar 5% infligido",
    "powerup_blood_aura_desc3": "Aura sangre {0} daño/s en radio 200, curar 10% infligido",
    "powerup_blood_mastery_desc": "Efectos sangre: +150% daño, +100% robo vida",
    "powerup_radial_burst_desc1": "Disparar 8 balas en círculo cada 3.5s (usa daño del jugador)",
    "powerup_radial_burst_desc2": "Disparar 10 balas en círculo cada 3.0s (usa daño del jugador)",
    "powerup_radial_burst_desc3": "Disparar 14 balas en círculo cada 2.0s (usa daño del jugador)",
    "powerup_wall_turrets_desc": "Muros disparan a enemigos (100 + {0} (15%) daño, enfriamiento 1.5s)",
    "powerup_pulse_armor_desc1": "Al recibir daño, empuja enemigos cercanos (sin daño, +1% maxHP escalado)",
    "powerup_pulse_armor_desc2": "Onda empuja más lejos e inflige 200 + 1% maxHP daño",
    "powerup_pulse_armor_desc3": "Onda empuja aún más lejos e inflige 400 + 1% maxHP daño",
    "powerup_heavy_rounds_desc1": "Balas 15% más grandes con ligero retroceso",
    "powerup_heavy_rounds_desc2": "Balas 25% más grandes con retroceso aumentado",
    "powerup_heavy_rounds_desc3": "Balas 35% más grandes con fuerte retroceso",
    "powerup_fortified_desc1": "Reduce daño recibido en 15% y gana 400 HP máximo",
    "powerup_fortified_desc2": "Reduce daño recibido en 25% y gana 800 (+400) HP máximo",
    "powerup_fortified_desc3": "Reduce daño recibido en 35% y gana 1200 (+400) HP máximo",
    "powerup_special_rounds_desc1": "Cada 5ta bala causa +75% daño de bonificación",
    "powerup_special_rounds_desc2": "Cada 4ta bala causa +75% daño de bonificación",
    "powerup_special_rounds_desc3": "Cada 3ra bala causa +75% daño de bonificación",
    "powerup_giant_slayer_desc1": "Causa 1% de HP actual del enemigo como daño extra",
    "powerup_giant_slayer_desc2": "Causa 1.75% de HP actual del enemigo como daño extra",
    "powerup_giant_slayer_desc3": "Causa 2.5% de HP actual del enemigo como daño extra",
    "powerup_celestial_veil_desc": "Absorbe 1 golpe por oleada — se reinicia al comienzo de cada oleada",
    
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
    "stats_time_warps": "Saltos Temporales",
    "stats_near_deaths": "Casi Muertes",
    "stats_best_streak": "Mejor Racha",
    "stats_time_at_low_hp": "Tiempo a HP Bajo",
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
    "stats_play_style_aggressive": "Agresivo",
    "stats_play_style_defensive": "Defensivo",
    "stats_play_style_mobile": "Móvil",
    "stats_play_style_tank": "Tanque",
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
    "game_over_continue": "> CONTINUAR",
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
    "shop_scroll_hint": "Rueda del ratón para ver más",
    "shop_click_equip": "Clic para equipar",
    "shop_window_title": "Tienda Personaliz.",
    "shop_equipped": "[EQUIPADO]",
    "shop_currently_equipped": "Equipado:",
    "shop_customize_appearance": "PERSONALIZA TU APARIENCIA",
    "shop_customize_bullets": "PERSONALIZA TUS BALAS",
    "shop_choose_shape": "ELIGE TU FORMA",
    "shop_customize_effects": "PERSONALIZA EFECTOS",
    
    # Player Skins
    "skin_default": "Sistema",
    "skin_default_desc": "Interfaz OS clásica",
    "skin_neon_pink": "Rosa Neón",
    "skin_neon_pink_desc": "Estilo cyberpunk",
    "skin_emerald": "Esmeralda",
    "skin_emerald_desc": "Tecnología verde",
    "skin_sunset": "Atardecer",
    "skin_sunset_desc": "Naranja y rojo ardiente",
    "skin_amethyst": "Amatista",
    "skin_amethyst_desc": "Energía púrpura",
    "skin_gold": "Dorado",
    "skin_gold_desc": "Brillo dorado",
    "skin_ice": "Cristal",
    "skin_ice_desc": "Belleza cristalina",
    "skin_shadow": "Sombra",
    "skin_shadow_desc": "Modo oscuro sigiloso",
    "skin_rainbow": "Arcoíris",
    "skin_rainbow_desc": "Espectro animado",
    "skin_matrix": "Matrix",
    "skin_matrix_desc": "Datos verdes",
    "skin_void": "Vacío",
    "skin_void_desc": "Energía del vacío",
    "skin_plasma": "Plasma",
    "skin_plasma_desc": "Plasma eléctrico",
    
    # Bullet Skins
    "bullet_default": "Sistema",
    "bullet_default_desc": "Proyectil clásico",
    "bullet_neon_pink": "Rosa Neón",
    "bullet_neon_pink_desc": "Proyectiles magenta",
    "bullet_emerald": "Esmeralda",
    "bullet_emerald_desc": "Energía verde",
    "bullet_sunset": "Atardecer",
    "bullet_sunset_desc": "Proyectiles naranja",
    "bullet_amethyst": "Amatista",
    "bullet_amethyst_desc": "Energía púrpura",
    "bullet_gold": "Dorado",
    "bullet_gold_desc": "Disparos dorados",
    "bullet_ice": "Cristal",
    "bullet_ice_desc": "Disparos cristalinos",
    "bullet_shadow": "Sombra",
    "bullet_shadow_desc": "Proyectiles oscuros",
    "bullet_rainbow": "Arcoíris",
    "bullet_rainbow_desc": "Espectro animado",
    "bullet_matrix": "Matrix",
    "bullet_matrix_desc": "Datos verdes",
    "bullet_void": "Vacío",
    "bullet_void_desc": "Energía del vacío",
    "bullet_plasma": "Plasma",
    "bullet_plasma_desc": "Plasma eléctrico",
    
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
    "particle_default": "Sistema",
    "particle_default_desc": "Energía estándar",
    "particle_fire": "Llamas",
    "particle_fire_desc": "Partículas de fuego",
    "particle_ice": "Escarcha",
    "particle_ice_desc": "Fragmentos helados",
    "particle_toxic": "Tóxico",
    "particle_toxic_desc": "Gas venenoso verde",
    "particle_plasma": "Plasma",
    "particle_plasma_desc": "Energía púrpura",
    "particle_gold": "Dorado",
    "particle_gold_desc": "Polvo dorado",
    "particle_shadow": "Humo",
    "particle_shadow_desc": "Rastros oscuros",
    "particle_rainbow": "Arcoíris",
    "particle_rainbow_desc": "Confeti colorido",
    "particle_stars": "Estrellas",
    "particle_stars_desc": "Partículas brillantes",
    "particle_hearts": "Corazones",
    "particle_hearts_desc": "Partículas lindas",
    "particle_lightning": "Relámpago",
    "particle_lightning_desc": "Rayos eléctricos",
    "particle_void": "Vacío",
    "particle_void_desc": "Grietas dimensionales",
    
    # Legendary Panel
    "legendary_panel_title": "LEGENDARIO",
    "legendary_chronos": "Chronos",
    "legendary_phase": "Phase",
    "legendary_parry": "Parada",
    "legendary_active": "ACTIVO",
    "legendary_ready": "Listo",
    "legendary_dashing": "SALTANDO",
    
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
    "help_enemies_topic": "TIPOS DE ENEMIGOS",
    "help_bosses_topic": "INFORMACIÓN DE JEFES",
    "help_shop_topic": "ARTÍCULOS DE TIENDA",
    "help_clear_command": "Limpiar la pantalla",
    "help_command_separator": "--------------------------------------",
    "help_launch_topics": "jugar/supervivencia/sandbox/estadísticas/ajustes/salir",
    "help_opening_settings": "Abriendo Settings.exe...",
    "help_launching_sandbox": "Lanzando Sandbox.exe...",
    "help_shutting_down": "Apagando...",
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
    "help_wind_aura": "Aura de Viento - Empuja enemigos lejos",
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
    
    # Help System - Shop items
    "help_shop_damage_plus": "Daño + (8 CR base)",
    "help_shop_damage_plus_desc": "Aumenta daño de balas",
    "help_shop_fire_rate_plus": "Tasa de Fuego + (10 CR base)",
    "help_shop_fire_rate_plus_desc": "Dispara más rápido",
    "help_shop_move_speed_plus": "Velocidad de Movimiento + (7 CR base)",
    "help_shop_move_speed_plus_desc": "Muévete más rápido",
    "help_shop_max_health_plus": "Salud Máxima + (10 CR base)",
    "help_shop_max_health_plus_desc": "Aumenta HP máximo",
    "help_shop_bullet_speed_plus": "Velocidad de Bala + (6 CR base)",
    "help_shop_bullet_speed_plus_desc": "Velocidad de bala más rápida",
    "help_shop_wall_x4": "Muro x4 (14 CR base)",
    "help_shop_wall_x4_desc": "Compra 4 muros desplegables",
    
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
    "help_cost_scaling_formula": "- Los costos aumentan con cada compra\n  - Cada compra: costo = costBase * 1.45^comprado",
    "help_kill_enemies_to_collect": "- Mata enemigos para recopilar monedas",
    "help_elite_drop_more": "- Los enemigos élite dejan caer más monedas",
    "help_boss_drop_large": "- Los jefes dejan caer grandes cantidades",
    "help_opens_after_powerup": "- Se abre después de seleccionar mejora",
    "help_available_between_waves": "- Disponible entre oleadas",
    
    # Game Notifications and UI
    "game_wave_announcement_main": "*** OLEADA ***",
    "game_instructions_wall": "E: Muro | ESC: Pausa",
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
    "sandbox_roll_power_ups": "Rodar Mejoras",
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
    
    # Power-up Installer
    "power_up_installer_title": "INSTALADOR DE MEJORA LEGENDARIA",
    "power_up_installer_title_generic": "ADMINISTRADOR DE ACTUALIZACIÓN DE PROCESOS",
    "power_up_upgrade_tier": "NIVEL DE ACTUALIZACIÓN:",
    "power_up_installer_close": "X",
    "power_up_select_upgrade": "v SELECCIONA MEJORA PARA INSTALAR:",
    "power_up_rolling": "[!] GIRANDO...",
    "power_up_reroll_options": "[R] Opción de Nuevo Intento",
    
    # Player Feedback
    "player_dodge": "¡ESQUIVA!",
    "player_parry": "¡PARRY!",
    "player_phase": "¡CAMBIO DE FASE!",
    "player_veil": "¡VELO!",
    
    # System Messages
    "system_defensive_processes": "Todos los procesos defensivos han sido terminados.",
    "system_press_any_key": "Presiona cualquier tecla para continuar...",
    "system_no_statistics": "No hay estadísticas disponibles",
    "system_press_esc_to_return": "Presiona ESC para volver",
    
    # Loading Screen
    "loading_title": "TopHat-ShooterOS",
    "loading_subtitle": "Edición v5.3",
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
    "os_system_paused": "Sistema pausado - presiona ESPACIO para continuar",
    "os_press_space_continue": "Presiona ESPACIO para continuar",
    
    # OS Desktop / System Info
    "os_system_monitor": "Monitor del Sistema",
    "os_cpu_idle": "CPU: Inactiva",
    "os_memory": "Memoria: 2.4 / 16 GB",
    "os_network": "Red: Conectada",
    "os_tophat_os": "TopHat-ShooterOS",
    "os_edition": "[Edición v5.3]",
    "os_tophat_button": "TopHat",
    "os_net_indicator": "RED",
    
    # Stats Labels
    "stats_system_analytics": "Análisis del Sistema",
    "stats_run_report": "Informe de Ejecución",
    "stats_wave_label": "Onda",
    "stats_time_label": "TIEMPO",
    "stats_kills_label": "ASESINATOS",
    "stats_accuracy_label": "PRECISIÓN",
    "stats_avg_dps": "DPS PROM",
    "stats_max_combo": "Combo Máx",
    "stats_avg_combo": "Combo Prom",
    "stats_perfect_waves": "Oleadas Perfectas",
    "stats_play_style_aggressive": "Agresivo",
    "stats_play_style_defensive": "Defensivo",
    "stats_play_style_mobile": "Móvil",
    "stats_play_style_tank": "Tanque",
    "stats_play_style_balanced": "Equilibrado",
    "stats_no_power_ups_selected": "Sin mejoras seleccionadas",
    "stats_no_graph_data_short": "Sin datos de gráfico",
    "stats_controls_footer": "[ENTER] Continuar  |  [ESC] Cerrar",
    "stats_wave_mode": "Modo Oleada",
    "stats_time_survival_mode": "Supervivencia Temporal",
    "stats_sandbox_mode": "Sandbox",
    "stats_pvp_mode": "PvP",
    "stats_bar_wave_max": "[OLEADA] Máximo Alcanzado",
    "stats_bar_kill_best": "[MUERTES] Mejor Rendimiento",
    "stats_bar_boss_eliminated": "[JEFE] Eliminado",
    "stats_bar_time_survival": "[TIEMPO] Supervivencia Más Larga",
    "stats_combat_label": "COMBATE",
    "stats_movement_label": "MOVIMIENTO Y SUPERVIVENCIA",
    "stats_performance_label": "RENDIMIENTO",
    "stats_resources_label": "RECURSOS",
    "stats_play_style_label": "ESTILO DE JUEGO",
    "stats_dps_over_time_label": "DPS A TRAVÉS DEL TIEMPO",
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
    
    # Achievement popup
    "achievement_unlocked": "¡LOGRO DESBLOQUEADO!",
    
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
    
    # Milestone / micro-reward popups
    "milestone_achievement": "Logro:",
    "massacre_bonus": "¡BONO MASACRE!",
    "wave_stats_flawless": "¡IMPECABLE!",
    "wave_stats_title": "OLEADA",
    "wave_stats_kills_label": "Muertes:",
    "wave_stats_time_label": "Tiempo:",
    
    # Milestone names & descriptions
    "milestone_first_boss_name": "PRIMER JEFE DERROTADO",
    "milestone_first_boss_desc": "Sobreviviste tu primer enfrentamiento con un jefe",
    "milestone_veteran_name": "SUPERVIVIENTE VETERANO",
    "milestone_veteran_desc": "Alcanzaste la oleada 10",
    "milestone_elite_name": "JUGADOR ÉLITE",
    "milestone_elite_desc": "Alcanzaste la oleada 25",
    "milestone_centurion_name": "CENTURIÓN",
    "milestone_centurion_desc": "Eliminaste 100 enemigos",
    "milestone_executioner_name": "VERDUGO",
    "milestone_executioner_desc": "Eliminaste 500 enemigos",
    "milestone_death_name": "LA MUERTE ENCARNADA",
    "milestone_death_desc": "Eliminaste 1000 enemigos",
    "milestone_wealthy_name": "ACAUDALADO",
    "milestone_wealthy_desc": "Recolectaste 1000 monedas en total",
    "milestone_tycoon_name": "MAGNATE",
    "milestone_tycoon_desc": "Recolectaste 5000 monedas en total",
    
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
    
    "stats_play_style_aggressive": "Agresivo",
    "stats_play_style_defensive": "Defensivo",
    "stats_play_style_mobile": "Móvil",
    "stats_play_style_tank": "Tanque",
    
    # Lifetime Stats Labels
    "stats_movement_label": "MOVIMIENTO",
    "stats_distance_label": "Distancia",
    "stats_phase_shifts_label": "Cambios de Fase",
    "stats_time_warps_label": "Saltos Temporales",
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
    "stats_play_style_label": "ESTILO DE JUEGO",
    "stats_aggression_label": "Agresión",
    "stats_caution_label": "Precaución",
    "stats_no_powerups_selected": "Sin mejoras seleccionadas",
    "stats_dps_over_time_label": "DPS A TRAVÉS DEL TIEMPO",
    "stats_no_graph_data_short": "Sin datos de gráfico",
    "stats_controls_footer": "[TAB/ESC] Volver  [R] Reiniciar  [Q] Menú",
    
    # Gamemode Names and Descriptions
    "gamemode_wave_based_name": "Por Oleadas",
    "gamemode_wave_based_desc": "Lucha contra oleadas de enemigos. Derrota a los jefes cada 5 oleadas para obtener mejoras legendarias.",
    "gamemode_time_survival_name": "Supervivencia por Tiempo",
    "gamemode_time_survival_desc": "Sobrevive el mayor tiempo posible. La dificultad aumenta con el tiempo.",
    "gamemode_sandbox_name": "Sandbox",
    "gamemode_sandbox_desc": "Prueba y experimenta con enemigos, jefes y mecánicas del juego.",
    "gamemode_pvp_name": "PVP",
    "gamemode_pvp_desc": "¡Batalla en tiempo real. Primero en 5 bajas gana!",
    
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
    "boss_12_desc": "El desafío final: combina todos los mecánicos anteriores"
  }.toTable
}.toTable

# Current language (default to English)
var currentLanguage*: Language = English

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

# Get current language
proc getLanguage*(): Language =
  return currentLanguage

# Get language name for display
proc getLanguageName*(lang: Language): string =
  case lang
  of English: "English"
  of Spanish: "Español"
