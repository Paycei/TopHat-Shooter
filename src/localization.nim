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
    tkSettingsKeyboardF = "settings_keyboard_f"
    tkSettingsKeyboardToggleAutoShoot = "settings_keyboard_toggle_auto_shoot"
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
    tkDebugPanelAutoShoot = "debug_panel_auto_shoot"
    tkDebugPanelAutoShootActive = "debug_panel_auto_shoot_active"
    tkDebugPanelAutoShootIdle = "debug_panel_auto_shoot_idle"
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
    tkHelpAutoShootReq = "help_auto_shoot_req"
    
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
    tkHelpDamageZone = "help_damage_zone"
    tkHelpMagicalBullets = "help_magical_bullets"
    tkHelpPiercingShots = "help_piercing_shots"
    tkHelpMultiShot = "help_multi_shot"
    tkHelpExplosiveBullets = "help_explosive_bullets"
    tkHelpLifeSteal = "help_life_steal"
    tkHelpRapidFire = "help_rapid_fire"
    tkHelpMaxHealth = "help_max_health"
    tkHelpSpeedBoost = "help_speed_boost"
    tkHelpBulletDamage = "help_bullet_damage"
    tkHelpBulletSpeed = "help_bullet_speed"
    tkHelpLuckyCoins = "help_lucky_coins"
    tkHelpWallMaster = "help_wall_master"
    tkHelpAutoShoot = "help_auto_shoot"
    tkHelpBulletSize = "help_bullet_size"
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
    tkPowerupDamageZone = "powerup_damage_zone"
    tkPowerupMagicalBullets = "powerup_magical_bullets"
    tkPowerupPiercingShots = "powerup_piercing_shots"
    tkPowerupMultiShot = "powerup_multi_shot"
    tkPowerupExplosiveBullets = "powerup_explosive_bullets"
    tkPowerupLifeSteal = "powerup_life_steal"
    tkPowerupRapidFire = "powerup_rapid_fire"
    tkPowerupMaxHealth = "powerup_max_health"
    tkPowerupSpeedBoost = "powerup_speed_boost"
    tkPowerupBulletDamage = "powerup_bullet_damage"
    tkPowerupBulletSpeed = "powerup_bullet_speed"
    tkPowerupLuckyCoins = "powerup_lucky_coins"
    tkPowerupWallMaster = "powerup_wall_master"
    tkPowerupAutoShoot = "powerup_auto_shoot"
    tkPowerupBulletSize = "powerup_bullet_size"
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
    
    # Powerup Descriptions (Level 1)
    tkPowerupDoubleShotDesc = "powerup_double_shot_desc"
    tkPowerupRotatingShieldDesc1 = "powerup_rotating_shield_desc1"
    tkPowerupRotatingShieldDesc2 = "powerup_rotating_shield_desc2"
    tkPowerupRotatingShieldDesc3 = "powerup_rotating_shield_desc3"
    tkPowerupDamageZoneDesc1 = "powerup_damage_zone_desc1"
    tkPowerupDamageZoneDesc2 = "powerup_damage_zone_desc2"
    tkPowerupDamageZoneDesc3 = "powerup_damage_zone_desc3"
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
    tkPowerupBulletDamageDesc = "powerup_bullet_damage_desc"
    tkPowerupBulletSpeedDesc = "powerup_bullet_speed_desc"
    tkPowerupLuckyCoinsDesc = "powerup_lucky_coins_desc"
    tkPowerupWallMasterDesc = "powerup_wall_master_desc"
    tkPowerupAutoShootDesc = "powerup_auto_shoot_desc"
    tkPowerupBulletSizeDesc1 = "powerup_bullet_size_desc1"
    tkPowerupBulletSizeDesc2 = "powerup_bullet_size_desc2"
    tkPowerupBulletSizeDesc3 = "powerup_bullet_size_desc3"
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
    
    # Player Feedback
    tkPlayerDodge = "player_dodge"
    tkPlayerParry = "player_parry"
    
    # System Messages
    tkSystemDefensiveProcesses = "system_defensive_processes"
    tkSystemPressAnyKey = "system_press_any_key"
    tkSystemNoStatistics = "system_no_statistics"
    tkSystemPressESCToReturn = "system_press_esc_to_return"
    
    # Cheat Menu Buttons
    tkCheatCloseInstruction = "cheat_close_instruction"
    tkCheatPressESCOrClick = "cheat_press_esc_or_click"
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
    
    # General
    tkYes = "general_yes"
    tkNo = "general_no"
    tkBack = "general_back"
    tkConfirm = "general_confirm"
    tkCancel = "general_cancel"

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
    "settings_keyboard_f": "F",
    "settings_keyboard_toggle_auto_shoot": "Toggle Auto-Shoot",
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
    "powerup_damage_zone": "Damage Aura",
    "powerup_magical_bullets": "Magical Bullets",
    "powerup_piercing_shots": "Piercing Shots",
    "powerup_multi_shot": "Multi-Shot",
    "powerup_explosive_bullets": "Explosive Rounds",
    "powerup_life_steal": "Life Steal",
    "powerup_rapid_fire": "Rapid Fire",
    "powerup_max_health": "Vitality",
    "powerup_speed_boost": "Agility",
    "powerup_bullet_damage": "Power",
    "powerup_bullet_speed": "Velocity",
    "powerup_lucky_coins": "Greed",
    "powerup_wall_master": "Fortify",
    "powerup_auto_shoot": "Auto-Target",
    "powerup_bullet_size": "Giant Bullets",
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
    
    # Powerup Descriptions
    "powerup_double_shot_desc": "Fire additional burst after 0.08s (-10% dmg per bullet, -25% fire rate)",
    "powerup_rotating_shield_desc1": "3 shields (30% coverage, 3 HP, 5.5s respawn)",
    "powerup_rotating_shield_desc2": "3 shields (35% coverage, 4 HP, 4.5s respawn)",
    "powerup_rotating_shield_desc3": "3 shields (40% coverage, 5 HP, 3.75s respawn)",
    "powerup_damage_zone_desc1": "3 dmg/sec in 120 radius (scales with crits)",
    "powerup_damage_zone_desc2": "6 dmg/sec in 160 radius (scales with crits)",
    "powerup_damage_zone_desc3": "12 dmg/sec in 200 radius (scales with crits)",
    "powerup_magical_bullets_desc": "Bullets track nearest enemy (scales with damage)",
    "powerup_piercing_shots_desc1": "Bullets pierce 1 enemy (-33% damage per pierce)",
    "powerup_piercing_shots_desc2": "Bullets pierce 2 enemies (-33% damage per pierce)",
    "powerup_piercing_shots_desc3": "Bullets pierce 3 enemies (-33% damage per pierce)",
    "powerup_multi_shot_desc": "Shoot in 3 directions",
    "powerup_explosive_bullets_desc1": "Bullets explode (small radius, scales with damage)",
    "powerup_explosive_bullets_desc2": "Bullets explode (medium radius, scales with damage)",
    "powerup_explosive_bullets_desc3": "Bullets explode (large radius, scales with damage)",
    "powerup_life_steal_desc1": "Heal 1 HP per 30 kills",
    "powerup_life_steal_desc2": "Heal 1 HP per 25 kills",
    "powerup_life_steal_desc3": "Heal 1 HP per 15 kills",
    "powerup_rapid_fire_desc": "+40% fire rate",
    "powerup_max_health_desc": "+14 max HP",
    "powerup_speed_boost_desc": "+40% movement speed",
    "powerup_bullet_damage_desc": "+75% bullet damage",
    "powerup_bullet_speed_desc": "+40% bullet speed",
    "powerup_lucky_coins_desc": "Doubles all coins collected",
    "powerup_wall_master_desc": "Walls have +250% HP turrets have +100% damage",
    "powerup_auto_shoot_desc": "Auto-fire at nearest enemy (90% fire rate, 450 range)",
    "powerup_bullet_size_desc1": "+50% bullet size",
    "powerup_bullet_size_desc2": "+100% bullet size",
    "powerup_bullet_size_desc3": "+150% bullet size",
    "powerup_regeneration_desc1": "Regen 1-2 HP per wave",
    "powerup_regeneration_desc2": "Regen 2-4 HP per wave",
    "powerup_regeneration_desc3": "Regen 3-6 HP per wave",
    "powerup_dodge_chance_desc1": "15% chance to dodge hits",
    "powerup_dodge_chance_desc2": "20% chance to dodge hits",
    "powerup_dodge_chance_desc3": "30% chance to dodge hits",
    "powerup_critical_hit_desc1": "20% chance for 2x damage (all sources)",
    "powerup_critical_hit_desc2": "35% chance for 2x damage (all sources)",
    "powerup_critical_hit_desc3": "50% chance for 2x damage (all sources)",
    "powerup_blood_bullets_desc1": "Heal 1.5% of bullet damage (blood element, +10% scaling)",
    "powerup_blood_bullets_desc2": "Heal 2% of bullet damage (blood element, +10% scaling)",
    "powerup_blood_bullets_desc3": "Heal 3% of bullet damage (blood element, +10% scaling)",
    "powerup_bullet_ricochet_desc1": "Bullets ricochet once (75% damage per ricochet)",
    "powerup_bullet_ricochet_desc2": "Bullets ricochet twice (75% damage per ricochet)",
    "powerup_bullet_ricochet_desc3": "Bullets ricochet 3 times (75% damage per ricochet)",
    "powerup_slow_field_desc1": "Slow enemies 30% in 120 radius",
    "powerup_slow_field_desc2": "Slow enemies 45% in 160 radius",
    "powerup_slow_field_desc3": "Slow enemies 55% in 200 radius",
    "powerup_rage_desc1": "+5% dmg per 10% HP lost",
    "powerup_rage_desc2": "+8% dmg per 10% HP lost",
    "powerup_rage_desc3": "+12% dmg per 10% HP lost",
    "powerup_berserker_desc1": "+5% fire rate per 10% HP lost",
    "powerup_berserker_desc2": "+8% fire rate per 10% HP lost",
    "powerup_berserker_desc3": "+12% fire rate per 10% HP lost",
    "powerup_thorns_desc1": "Reflect 50% damage to attacker (scales with max HP)",
    "powerup_thorns_desc2": "Reflect 100% damage to attacker (scales with max HP)",
    "powerup_thorns_desc3": "Reflect 200% damage to attacker (scales with max HP)",
    "powerup_bullet_split_desc1": "Bullets split into 2 on hit",
    "powerup_bullet_split_desc2": "Bullets split into 3 on hit",
    "powerup_bullet_split_desc3": "Bullets split into 4 on hit",
    "powerup_chain_lightning_desc1": "Hit chains to 1 enemy (70% dmg, 120 range, 0.05s stun)",
    "powerup_chain_lightning_desc2": "Hit chains to 2 enemies (85% dmg, 140 range, 0.05s stun)",
    "powerup_chain_lightning_desc3": "Hit chains to 3 enemies (100% dmg, 160 range, 0.05s stun)",
    "powerup_frost_shots_desc1": "Bullets slow enemies 25% (permanent)",
    "powerup_frost_shots_desc2": "Bullets slow enemies 40% (permanent)",
    "powerup_frost_shots_desc3": "Bullets slow enemies 60% (permanent)",
    "powerup_poison_shot_desc1": "Bullets poison (0.5 dmg/s, 4s, +10% scaling)",
    "powerup_poison_shot_desc2": "Bullets poison (1 dmg/s, 5s, +10% scaling)",
    "powerup_poison_shot_desc3": "Bullets poison (2 dmg/s, 6s, +10% scaling)",
    "powerup_fire_bullets_desc1": "Bullets burn (0.3 dmg/s, 2s, +10% scaling)",
    "powerup_fire_bullets_desc2": "Bullets burn (0.75 dmg/s, 3s, +10% scaling)",
    "powerup_fire_bullets_desc3": "Bullets burn (1.5 dmg/s, 4s, +10% scaling)",
    "powerup_wind_bullets_desc1": "Bullets knock back enemies (weak push)",
    "powerup_wind_bullets_desc2": "Bullets knock back enemies (medium push)",
    "powerup_wind_bullets_desc3": "Bullets knock back enemies (strong push)",
    "powerup_fire_aura_desc1": "Burn enemies 1.5 dmg/s in 120 radius (2s, +20% scaling)",
    "powerup_fire_aura_desc2": "Burn enemies 3 dmg/s in 160 radius (3s, +20% scaling)",
    "powerup_fire_aura_desc3": "Burn enemies 6 dmg/s in 200 radius (4s, +20% scaling)",
    "powerup_lightning_aura_desc1": "Zap 0.8 dmg/s in 120 radius (chains 1x, +20% scaling)",
    "powerup_lightning_aura_desc2": "Zap 1.6 dmg/s in 160 radius (chains 2x, +20% scaling)",
    "powerup_lightning_aura_desc3": "Zap 3.2 dmg/s in 200 radius (chains 3x, +20% scaling)",
    "powerup_poison_aura_desc1": "Poison 0.6 dmg/s in 120 radius (6s duration, +20% scaling)",
    "powerup_poison_aura_desc2": "Poison 1.2 dmg/s in 160 radius (8s duration, +20% scaling)",
    "powerup_poison_aura_desc3": "Poison 2.4 dmg/s in 200 radius (10s duration, +20% scaling)",
    "powerup_wind_aura_desc1": "Push enemies away in 120 radius (weak)",
    "powerup_wind_aura_desc2": "Push enemies away in 160 radius (medium)",
    "powerup_wind_aura_desc3": "Push enemies away in 200 radius (strong)",
    "powerup_time_warp_desc": "Slow time 50% for 3.5s (2 uses/wave, 10s cd)",
    "powerup_gravity_well_desc": "Pull enemies in 300 radius",
    "powerup_phase_shift_desc": "Dash forward (5s cd, 0.5s invuln, scales with speed)",
    "powerup_overcharge_desc": "+10% dmg per 100 units traveled (max 150%, reaches at 1000 units)",
    "powerup_echo_shots_desc": "Bullets leave ghost trail (60% dmg, scales with damage)",
    "powerup_rotating_orbs_desc": "All 6 elemental orbs (6 dmg/hit)",
    "powerup_poison_orb_desc1": "2 poison orbs (0.3 dmg/s, +10% scaling)",
    "powerup_poison_orb_desc2": "4 poison orbs (0.3 dmg/s, +10% scaling)",
    "powerup_poison_orb_desc3": "6 poison orbs (0.3 dmg/s, +10% scaling)",
    "powerup_fire_orb_desc1": "2 fire orbs (0.4 dmg/s, +10% scaling)",
    "powerup_fire_orb_desc2": "4 fire orbs (0.4 dmg/s, +10% scaling)",
    "powerup_fire_orb_desc3": "6 fire orbs (0.4 dmg/s, +10% scaling)",
    "powerup_lightning_orb_desc1": "2 lightning orbs (1 dmg/hit, +10% scaling)",
    "powerup_lightning_orb_desc2": "4 lightning orbs (2 dmg/hit, +10% scaling)",
    "powerup_lightning_orb_desc3": "6 lightning orbs (3 dmg/hit, +10% scaling)",
    "powerup_wind_orb_desc1": "2 wind orbs (1 dmg/hit, push, +10% scaling)",
    "powerup_wind_orb_desc2": "4 wind orbs (2 dmg/hit, push, +10% scaling)",
    "powerup_wind_orb_desc3": "6 wind orbs (3 dmg/hit, push, +10% scaling)",
    "powerup_frost_orb_desc1": "2 frost orbs (1 dmg/hit, slow, +10% scaling)",
    "powerup_frost_orb_desc2": "4 frost orbs (2 dmg/hit, slow, +10% scaling)",
    "powerup_frost_orb_desc3": "6 frost orbs (3 dmg/hit, slow, +10% scaling)",
    "powerup_arcane_orb_desc1": "2 arcane orbs (1 dmg/hit, arcane, +10% scaling)",
    "powerup_arcane_orb_desc2": "4 arcane orbs (2 dmg/hit, arcane, +10% scaling)",
    "powerup_arcane_orb_desc3": "6 arcane orbs (3 dmg/hit, arcane, +10% scaling)",
    "powerup_arcane_bullets_desc1": "Bullets enhanced with arcane power (+50% bullet damage, arcane)",
    "powerup_arcane_bullets_desc2": "Bullets enhanced with arcane power (+85% bullet damage, arcane)",
    "powerup_arcane_bullets_desc3": "Bullets enhanced with arcane power (+120% bullet damage, arcane)",
    "powerup_arcane_aura_desc1": "Arcane aura 2 dmg/s in 120 radius, arcane (+20% scaling)",
    "powerup_arcane_aura_desc2": "Arcane aura 4 dmg/s in 160 radius, arcane (+20% scaling)",
    "powerup_arcane_aura_desc3": "Arcane aura 8 dmg/s in 200 radius, arcane (+20% scaling)",
    "powerup_fire_mastery_desc": "Fire effects: +150% dmg, +100% duration, +35% slow",
    "powerup_poison_mastery_desc": "Poison effects: +150% dmg, +100% duration, +30% slow",
    "powerup_frost_mastery_desc": "Frost effects: +150% dmg, +100% duration, +20% slow",
    "powerup_arcane_mastery_desc": "Arcane effects: +100% dmg, piercing",
    "powerup_lightning_mastery_desc": "Lightning effects: +150% dmg, +25% slow, +1 chain, +50% range",
    "powerup_wind_mastery_desc": "Wind effects: +150% dmg, +40% slow, stronger push",
    "powerup_parry_desc": "Active: Invincible for 0.5s, bounce enemy bullets (5s cooldown)",
    "powerup_blood_orb_desc1": "2 blood orbs (1 dmg/hit, lifesteal, +10% scaling)",
    "powerup_blood_orb_desc2": "4 blood orbs (2 dmg/hit, lifesteal, +10% scaling)",
    "powerup_blood_orb_desc3": "6 blood orbs (3 dmg/hit, lifesteal, +10% scaling)",
    "powerup_blood_aura_desc1": "Blood aura 1.5 dmg/s in 120 radius, heal 2.5% dealt (+20% scaling)",
    "powerup_blood_aura_desc2": "Blood aura 3 dmg/s in 160 radius, heal 5% dealt (+20% scaling)",
    "powerup_blood_aura_desc3": "Blood aura 6 dmg/s in 200 radius, heal 10% dealt (+20% scaling)",
    "powerup_blood_mastery_desc": "Blood effects: +150% dmg, +100% duration, +50% lifesteal",
    "powerup_radial_burst_desc1": "Fire 8 bullets in a circle every 4s (scales with damage)",
    "powerup_radial_burst_desc2": "Fire 10 bullets in a circle every 3s (scales with damage)",
    "powerup_radial_burst_desc3": "Fire 14 bullets in a circle every 2s (scales with damage)",
    "powerup_wall_turrets_desc": "Walls shoot enemies (1 dmg, 2s cooldown, scales with Wall Master)",
    "powerup_pulse_armor_desc1": "Taking damage pushes nearby enemies back (scales with max HP)",
    "powerup_pulse_armor_desc2": "Shockwave pushes further and deals 2 damage (scales with max HP)",
    "powerup_pulse_armor_desc3": "Shockwave pushes even further and deals 4 damage (scales with max HP)",
    "powerup_heavy_rounds_desc1": "Bullets 15% larger with slight knockback",
    "powerup_heavy_rounds_desc2": "Bullets 25% larger with increased knockback",
    "powerup_heavy_rounds_desc3": "Bullets 35% larger with strong knockback",
    "powerup_fortified_desc1": "Reduce damage taken by 10%",
    "powerup_fortified_desc2": "Reduce damage taken by 15%",
    "powerup_fortified_desc3": "Reduce damage taken by 20%",
    
    # Player Feedback
    "player_dodge": "DODGE!",
    "player_parry": "PARRY!",
    
    # System Messages
    "system_defensive_processes": "All defensive processes have been terminated.",
    "system_press_any_key": "Press almost any key to continue...",
    "system_no_statistics": "No statistics available",
    "system_press_esc_to_return": "Press ESC to return",
    
    # Cheat Menu Buttons
    "cheat_close_instruction": "Press ESC or click X to close",
    "cheat_press_esc_or_click": "Press ESC or click X to close",
    "cheat_showing_items": "Showing",
    "cheat_scroll_up": "UP to scroll up",
    "cheat_scroll_down": "DOWN to scroll down",
    "cheat_no_power_ups_selected": "No power-ups selected",
    
    # OS Task Manager / System Monitoring
    "os_running_processes": "RUNNING PROCESSES:",
    "os_no_active_processes": "No active processes",
    "os_process_name": "Process Name",
    "os_version": "Version",
    "os_status": "Status",
    "os_system_performance": "SYSTEM PERFORMANCE:",
    "os_system_manager": "System Manager",
    "os_system_paused": "System paused - press SPACE to continue",
    "os_press_space_continue": "Press SPACE to continue",
    
    # OS Desktop / System Info
    "os_system_monitor": "System Monitor",
    "os_cpu_idle": "CPU: Idle",
    "os_memory": "Memory: 2.4 / 16 GB",
    "os_network": "Network: Connected",
    "os_tophat_os": "TopHat-ShooterOS",
    "os_edition": "[v5.1 Edition]",
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
    
    # Enemy Labels
    "enemy_active_threats": "ACTIVE THREATS:",
    
    # General
    "general_yes": "Yes",
    "general_no": "No",
    "general_back": "Back",
    "general_confirm": "Confirm",
    "general_cancel": "Cancel",
    
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
    "debug_panel_auto_shoot": "AutoShoot",
    "debug_panel_auto_shoot_active": "ACTIVE",
    "debug_panel_auto_shoot_idle": "IDLE",
    "debug_panel_low_hp_bonuses": "Low HP Bonuses",
    "debug_panel_rage": "Rage",
    "debug_panel_berserker": "Berserk",
    
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
    "help_f": "F .................. Toggle Auto-Shoot*",
    "help_q": "Q .................. Activate Legendary Powers",
    "help_e": "E .................. Place Wall",
    "help_esc": "ESC ................ Pause / Return to menu",
    "help_f11": "F11 ................ Toggle Fullscreen",
    "help_auto_shoot_req": "* Requires Auto-Shoot power-up",
    
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
    "help_damage_zone": "Damage Zone - Passive damage aura",
    "help_magical_bullets": "Magical Bullets - Bullets track enemies",
    "help_piercing_shots": "Piercing Shots - Bullets pass through enemies",
    "help_multi_shot": "Multi Shot - Shoots in 3 directions",
    "help_explosive_bullets": "Explosive Bullets - Bullets explode on impact",
    "help_life_steal": "Life Steal - Gain HP from kills",
    "help_rapid_fire": "Rapid Fire - Increased fire rate",
    "help_max_health": "Max Health - Increase max HP",
    "help_speed_boost": "Speed Boost - Permanent speed increase",
    "help_bullet_damage": "Bullet Damage - Increased bullet damage",
    "help_bullet_speed": "Bullet Speed - Faster bullets",
    "help_lucky_coins": "Lucky Coins - Doubles coins collected",
    "help_wall_master": "Wall Master - Place stronger walls",
    "help_auto_shoot": "Auto Shoot - Auto-target nearest enemy",
    "help_bullet_size": "Bullet Size - Larger projectiles",
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
    "power_up_reroll_options": "[R] Reroll Options"
  }.toTable,
  
  Spanish: {
    # Main Menu
    "menu_play": "jugar",
    "menu_survival": "supervivencia",
    "menu_stats": "estadísticas",
    "menu_help": "ayuda",
    "menu_settings": "ajustes",
    "menu_quit": "salir",
    "menu_sandbox": "sandbox",
    
    # Settings
    "settings_title": "AJUSTES",
    "settings_fps_limit": "Límite de FPS:",
    "settings_click_edit": "Haz clic para editar, Enter para confirmar",
    "settings_sound_effects": "Efectos de Sonido:",
    "settings_music": "Música:",
    "settings_fullscreen": "Pantalla Completa:",
    "settings_fullscreen_toggle": "(Presiona F11 para cambiar)",
    "settings_show_fps": "Mostrar FPS:",
    "settings_mouse_support": "Soporte de Ratón:",
    "settings_mouse_support_desc": "(nueva navegación de menú)",
    "settings_show_cursor": "Mostrar Cursor:",
    "settings_show_cursor_desc": "(solo visual)",
    "settings_debug_panel": "Panel de Depuración:",
    "settings_debug_panel_desc": "(estadísticas arriba-derecha)",
    "settings_show_hints": "Mostrar Consejos:",
    "settings_show_hints_desc": "(E: Muro, ESC: Pausa)",
    "settings_show_enemy_labels": "Mostrar Etiquetas de Enemigos:",
    "settings_show_enemy_labels_desc": "(etiquetas sobre enemigos)",
    "settings_language": "Idioma:",
    "settings_back_to_menu": "Presiona ESC para volver al menú",
    
    # Settings window tabs and sections
    "settings_tab_graphics": "Gráficos",
    "settings_tab_audio": "Audio",
    "settings_tab_controls": "Controles",
    "settings_tab_gameplay": "Juego",
    
    "settings_section_display": "PANTALLA",
    "settings_section_volume_control": "CONTROL DE VOLUMEN",
    "settings_section_input_method": "MÉTODO DE ENTRADA",
    "settings_section_assistance": "ASISTENCIA",
    "settings_section_localization": "LOCALIZACIÓN",
    "settings_section_keyboard_shortcuts": "ATAJOS DE TECLADO",
    
    "settings_keyboard_wasd": "WASD / Flechas",
    "settings_keyboard_movement": "Movimiento",
    "settings_keyboard_mouse_space": "Ratón / Espacio",
    "settings_keyboard_shoot": "Disparar",
    "settings_keyboard_f": "F",
    "settings_keyboard_toggle_auto_shoot": "Alternar Disparo Automático",
    "settings_keyboard_e": "E",
    "settings_keyboard_place_wall": "Colocar Muro",
    "settings_keyboard_q": "Q",
    "settings_keyboard_legendary_abilities": "Habilidades Legendarias",
    "settings_keyboard_esc": "ESC",
    "settings_keyboard_pause_menu": "Pausa / Menú",
    "settings_keyboard_f11": "F11",
    "settings_keyboard_toggle_fullscreen": "Alternar Pantalla Completa",
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
    "shop_credit_store": "TIENDA DE CRÉDITOS - MEJORAS DISPONIBLES",
    "shop_upgrades_available": "MEJORAS DISPONIBLES",
    "shop_active_upgrades": "MEJORAS ACTIVAS",
    "shop_available_purchases": "COMPRAS DISPONIBLES:",
    "shop_controls": "CONTROLES:",
    "shop_navigate": "Navegar",
    "shop_continue": "Continuar",
    "shop_buy_selected": "COMPRAR SELECCIONADO",
    "shop_insufficient_credits": "CRÉDITOS INSUFICIENTES",
    "shop_no_permanent": "Aún no hay mejoras permanentes.",
    "shop_defeat_waves": "¡Derrota oleadas para desbloquear!",
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
    "powerup_damage_zone": "Aura de Daño",
    "powerup_magical_bullets": "Balas Mágicas",
    "powerup_piercing_shots": "Disparos Perforantes",
    "powerup_multi_shot": "Multidisparo",
    "powerup_explosive_bullets": "Balas Explosivas",
    "powerup_life_steal": "Robo de Vida",
    "powerup_rapid_fire": "Fuego Rápido",
    "powerup_max_health": "Vitalidad",
    "powerup_speed_boost": "Agilidad",
    "powerup_bullet_damage": "Poder",
    "powerup_bullet_speed": "Velocidad",
    "powerup_lucky_coins": "Codicia",
    "powerup_wall_master": "Fortificar",
    "powerup_auto_shoot": "Apuntado Auto",
    "powerup_bullet_size": "Balas Gigantes",
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
    
    # Powerup Descriptions
    "powerup_double_shot_desc": "Disparar ráfaga adicional después de 0.08s (-10% daño por bala, -25% cadencia)",
    "powerup_rotating_shield_desc1": "3 escudos (30% cobertura, 3 HP, 5.5s reaparición)",
    "powerup_rotating_shield_desc2": "3 escudos (35% cobertura, 4 HP, 4.5s reaparición)",
    "powerup_rotating_shield_desc3": "3 escudos (40% cobertura, 5 HP, 3.75s reaparición)",
    "powerup_damage_zone_desc1": "3 daño/seg en radio 120",
    "powerup_damage_zone_desc2": "6 daño/seg en radio 160",
    "powerup_damage_zone_desc3": "12 daño/seg en radio 200",
    "powerup_magical_bullets_desc": "Balas rastrean enemigo más cercano (escala con daño)",
    "powerup_piercing_shots_desc1": "Balas perforan 1 enemigo (-33% daño por perforación)",
    "powerup_piercing_shots_desc2": "Balas perforan 2 enemigos (-33% daño por perforación)",
    "powerup_piercing_shots_desc3": "Balas perforan 3 enemigos (-33% daño por perforación)",
    "powerup_multi_shot_desc": "Disparar en 3 direcciones",
    "powerup_explosive_bullets_desc1": "Balas explotan (radio pequeño, escala con daño)",
    "powerup_explosive_bullets_desc2": "Balas explotan (radio mediano, escala con daño)",
    "powerup_explosive_bullets_desc3": "Balas explotan (radio grande, escala con daño)",
    "powerup_life_steal_desc1": "Curar 1 HP cada 30 muertes",
    "powerup_life_steal_desc2": "Curar 1 HP cada 25 muertes",
    "powerup_life_steal_desc3": "Curar 1 HP cada 15 muertes",
    "powerup_rapid_fire_desc": "+40% cadencia de fuego",
    "powerup_max_health_desc": "+14 HP máximo",
    "powerup_speed_boost_desc": "+40% velocidad movimiento",
    "powerup_bullet_damage_desc": "+75% daño de balas",
    "powerup_bullet_speed_desc": "+40% velocidad de balas",
    "powerup_lucky_coins_desc": "Duplica todas las monedas recogidas",
    "powerup_wall_master_desc": "Muros tienen +250% HP torretas +100% daño",
    "powerup_auto_shoot_desc": "Disparo auto al enemigo más cercano (90% cadencia, rango 450)",
    "powerup_bullet_size_desc1": "+50% tamaño de bala",
    "powerup_bullet_size_desc2": "+100% tamaño de bala",
    "powerup_bullet_size_desc3": "+150% tamaño de bala",
    "powerup_regeneration_desc1": "Regen 1-2 HP por oleada",
    "powerup_regeneration_desc2": "Regen 2-4 HP por oleada",
    "powerup_regeneration_desc3": "Regen 3-6 HP por oleada",
    "powerup_dodge_chance_desc1": "15% probabilidad esquivar golpes",
    "powerup_dodge_chance_desc2": "20% probabilidad esquivar golpes",
    "powerup_dodge_chance_desc3": "30% probabilidad esquivar golpes",
    "powerup_critical_hit_desc1": "20% probabilidad de 2x daño (todas fuentes)",
    "powerup_critical_hit_desc2": "35% probabilidad de 2x daño (todas fuentes)",
    "powerup_critical_hit_desc3": "50% probabilidad de 2x daño (todas fuentes)",
    "powerup_blood_bullets_desc1": "Curar 1.5% del daño de bala (elemento sangre)",
    "powerup_blood_bullets_desc2": "Curar 2% del daño de bala (elemento sangre)",
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
    "powerup_thorns_desc1": "Reflejar 50% daño al atacante (escala con max HP)",
    "powerup_thorns_desc2": "Reflejar 100% daño al atacante (escala con max HP)",
    "powerup_thorns_desc3": "Reflejar 200% daño al atacante (escala con max HP)",
    "powerup_bullet_split_desc1": "Balas se dividen en 2 al impactar",
    "powerup_bullet_split_desc2": "Balas se dividen en 3 al impactar",
    "powerup_bullet_split_desc3": "Balas se dividen en 4 al impactar",
    "powerup_chain_lightning_desc1": "Golpe encadena a 1 enemigo (70% daño, rango 120, aturdimiento 0.05s)",
    "powerup_chain_lightning_desc2": "Golpe encadena a 2 enemigos (85% daño, rango 140, aturdimiento 0.05s)",
    "powerup_chain_lightning_desc3": "Golpe encadena a 3 enemigos (100% daño, rango 160, aturdimiento 0.05s)",
    "powerup_frost_shots_desc1": "Balas ralentizan enemigos 25% (permanente)",
    "powerup_frost_shots_desc2": "Balas ralentizan enemigos 40% (permanente)",
    "powerup_frost_shots_desc3": "Balas ralentizan enemigos 60% (permanente)",
    "powerup_poison_shot_desc1": "Balas envenenan (0.5 daño/s, 4s)",
    "powerup_poison_shot_desc2": "Balas envenenan (1 daño/s, 5s)",
    "powerup_poison_shot_desc3": "Balas envenenan (2 daño/s, 6s)",
    "powerup_fire_bullets_desc1": "Balas queman (0.3 daño/s, 2s)",
    "powerup_fire_bullets_desc2": "Balas queman (0.75 daño/s, 3s)",
    "powerup_fire_bullets_desc3": "Balas queman (1.5 daño/s, 4s)",
    "powerup_wind_bullets_desc1": "Balas empujan enemigos (empuje débil)",
    "powerup_wind_bullets_desc2": "Balas empujan enemigos (empuje medio)",
    "powerup_wind_bullets_desc3": "Balas empujan enemigos (empuje fuerte)",
    "powerup_fire_aura_desc1": "Quemar enemigos 1.5 daño/s en radio 120 (2s)",
    "powerup_fire_aura_desc2": "Quemar enemigos 3 daño/s en radio 160 (3s)",
    "powerup_fire_aura_desc3": "Quemar enemigos 6 daño/s en radio 200 (4s)",
    "powerup_lightning_aura_desc1": "Electrocutar 0.8 daño/s en radio 120 (encadena 1x)",
    "powerup_lightning_aura_desc2": "Electrocutar 1.6 daño/s en radio 160 (encadena 2x)",
    "powerup_lightning_aura_desc3": "Electrocutar 3.2 daño/s en radio 200 (encadena 3x)",
    "powerup_poison_aura_desc1": "Veneno 0.6 daño/s en radio 120 (duración 6s)",
    "powerup_poison_aura_desc2": "Veneno 1.2 daño/s en radio 160 (duración 8s)",
    "powerup_poison_aura_desc3": "Veneno 2.4 daño/s en radio 200 (duración 10s)",
    "powerup_wind_aura_desc1": "Empujar enemigos en radio 120 (débil)",
    "powerup_wind_aura_desc2": "Empujar enemigos en radio 160 (medio)",
    "powerup_wind_aura_desc3": "Empujar enemigos en radio 200 (fuerte)",
    "powerup_time_warp_desc": "Ralentizar tiempo 50% por 3.5s (2 usos/oleada, 10s cd)",
    "powerup_gravity_well_desc": "Atraer enemigos en radio 300",
    "powerup_phase_shift_desc": "Dash adelante (5s cd, 0.5s invuln, escala con velocidad)",
    "powerup_overcharge_desc": "+10% daño por 100 unidades recorridas (max 150%, rango 1000)",
    "powerup_echo_shots_desc": "Balas dejan rastro fantasma (60% daño, escala con daño)",
    "powerup_rotating_orbs_desc": "Los 6 orbes elementales (6 daño/golpe)",
    "powerup_poison_orb_desc1": "2 orbes veneno (0.3 daño/s)",
    "powerup_poison_orb_desc2": "4 orbes veneno (0.3 daño/s)",
    "powerup_poison_orb_desc3": "6 orbes veneno (0.3 daño/s)",
    "powerup_fire_orb_desc1": "2 orbes fuego (0.4 daño/s)",
    "powerup_fire_orb_desc2": "4 orbes fuego (0.4 daño/s)",
    "powerup_fire_orb_desc3": "6 orbes fuego (0.4 daño/s)",
    "powerup_lightning_orb_desc1": "2 orbes rayo (1 daño/golpe, +10% escalado)",
    "powerup_lightning_orb_desc2": "4 orbes rayo (2 daño/golpe, +10% escalado)",
    "powerup_lightning_orb_desc3": "6 orbes rayo (3 daño/golpe, +10% escalado)",
    "powerup_wind_orb_desc1": "2 orbes viento (1 daño/golpe, empuje, +10% escalado)",
    "powerup_wind_orb_desc2": "4 orbes viento (2 daño/golpe, empuje, +10% escalado)",
    "powerup_wind_orb_desc3": "6 orbes viento (3 daño/golpe, empuje, +10% escalado)",
    "powerup_frost_orb_desc1": "2 orbes hielo (1 daño/golpe, ralentizar, +10% escalado)",
    "powerup_frost_orb_desc2": "4 orbes hielo (2 daño/golpe, ralentizar, +10% escalado)",
    "powerup_frost_orb_desc3": "6 orbes hielo (3 daño/golpe, ralentizar, +10% escalado)",
    "powerup_arcane_orb_desc1": "2 orbes arcanos (1 daño/golpe, arcano, +10% escalado)",
    "powerup_arcane_orb_desc2": "4 orbes arcanos (2 daño/golpe, arcano, +10% escalado)",
    "powerup_arcane_orb_desc3": "6 orbes arcanos (3 daño/golpe, arcano, +10% escalado)",
    "powerup_arcane_bullets_desc1": "Balas mejoradas con poder arcano (+50% daño bala, arcano)",
    "powerup_arcane_bullets_desc2": "Balas mejoradas con poder arcano (+85% daño bala, arcano)",
    "powerup_arcane_bullets_desc3": "Balas mejoradas con poder arcano (+120% daño bala, arcano)",
    "powerup_arcane_aura_desc1": "Aura arcana 2 daño/s en radio 120, arcano",
    "powerup_arcane_aura_desc2": "Aura arcana 4 daño/s en radio 160, arcano",
    "powerup_arcane_aura_desc3": "Aura arcana 8 daño/s en radio 200, arcano",
    "powerup_fire_mastery_desc": "Efectos fuego: +150% daño, +100% duración, +35% ralentización",
    "powerup_poison_mastery_desc": "Efectos veneno: +150% daño, +100% duración, +30% ralentización",
    "powerup_frost_mastery_desc": "Efectos hielo: +150% daño, +100% duración, +20% ralentización",
    "powerup_arcane_mastery_desc": "Efectos arcanos: +100% daño, perforación",
    "powerup_lightning_mastery_desc": "Efectos rayo: +150% daño, +25% ralentización, +1 cadena, +50% rango",
    "powerup_wind_mastery_desc": "Efectos viento: +150% daño, +40% ralentización, empuje más fuerte",
    "powerup_parry_desc": "Activo: Invencible por 0.5s, rebota balas enemigas (5s enfriamiento)",
    "powerup_blood_orb_desc1": "2 orbes sangre (1 daño/golpe, robo vida, +10% escalado)",
    "powerup_blood_orb_desc2": "4 orbes sangre (2 daño/golpe, robo vida, +10% escalado)",
    "powerup_blood_orb_desc3": "6 orbes sangre (3 daño/golpe, robo vida, +10% escalado)",
    "powerup_blood_aura_desc1": "Aura sangre 1.5 daño/s en radio 120, curar 2.5% infligido",
    "powerup_blood_aura_desc2": "Aura sangre 3 daño/s en radio 160, curar 5% infligido",
    "powerup_blood_aura_desc3": "Aura sangre 6 daño/s en radio 200, curar 10% infligido",
    "powerup_blood_mastery_desc": "Efectos sangre: +150% daño, +100% duración, +50% robo vida",
    "powerup_radial_burst_desc1": "Disparar 8 balas en círculo cada 4s (escala con daño)",
    "powerup_radial_burst_desc2": "Disparar 10 balas en círculo cada 3s (escala con daño)",
    "powerup_radial_burst_desc3": "Disparar 14 balas en círculo cada 2s (escala con daño)",
    "powerup_wall_turrets_desc": "Muros disparan a enemigos (1 daño, 2s enfriamiento, escala con Wall Master)",
    "powerup_pulse_armor_desc1": "Al recibir daño, empuja enemigos cercanos (escala con max HP)",
    "powerup_pulse_armor_desc2": "Onda empuja más lejos e inflige 2 de daño (escala con max HP)",
    "powerup_pulse_armor_desc3": "Onda empuja aún más lejos e inflige 4 de daño (escala con max HP)",
    "powerup_heavy_rounds_desc1": "Balas 15% más grandes con ligero retroceso",
    "powerup_heavy_rounds_desc2": "Balas 25% más grandes con retroceso aumentado",
    "powerup_heavy_rounds_desc3": "Balas 35% más grandes con fuerte retroceso",
    "powerup_fortified_desc1": "Reduce daño recibido en 10%",
    "powerup_fortified_desc2": "Reduce daño recibido en 15%",
    "powerup_fortified_desc3": "Reduce daño recibido en 20%",
    
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
    "debug_panel_auto_shoot": "Disparo Auto",
    "debug_panel_auto_shoot_active": "ACTIVO",
    "debug_panel_auto_shoot_idle": "INACTIVO",
    "debug_panel_low_hp_bonuses": "Bonificaciones Bajo HP",
    "debug_panel_rage": "Furia",
    "debug_panel_berserker": "Berserker",
    
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
    "help_f": "F .................. Alternar Disparo Automático*",
    "help_q": "Q .................. Activar Poderes Legendarios",
    "help_e": "E .................. Colocar Muro",
    "help_esc": "ESC ................ Pausa / Volver al menú",
    "help_f11": "F11 ................ Alternar Pantalla Completa",
    "help_auto_shoot_req": "* Requiere la mejora Disparo Automático",
    
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
    "help_damage_zone": "Zona de Daño - Aura de daño pasiva",
    "help_magical_bullets": "Balas Mágicas - Las balas rastrean enemigos",
    "help_piercing_shots": "Disparos Penetrantes - Las balas pasan por enemigos",
    "help_multi_shot": "Disparo Múltiple - Dispara en 3 direcciones",
    "help_explosive_bullets": "Balas Explosivas - Las balas explotan al impacto",
    "help_life_steal": "Robo de Vida - Gana HP al matar",
    "help_rapid_fire": "Fuego Rápido - Tasa de fuego aumentada",
    "help_max_health": "Salud Máxima - Aumenta HP máximo",
    "help_speed_boost": "Aumento de Velocidad - Aumento de velocidad permanente",
    "help_bullet_damage": "Daño de Balas - Daño de balas aumentado",
    "help_bullet_speed": "Velocidad de Balas - Balas más rápidas",
    "help_lucky_coins": "Monedas Afortunadas - Duplica monedas recolectadas",
    "help_wall_master": "Maestro de Muros - Coloca muros más fuertes",
    "help_auto_shoot": "Disparo Automático - Apunta automáticamente al enemigo más cercano",
    "help_bullet_size": "Tamaño de Bala - Proyectiles más grandes",
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
    
    # System Messages
    "system_defensive_processes": "Todos los procesos defensivos han sido terminados.",
    "system_press_any_key": "Presiona cualquier tecla para continuar...",
    "system_no_statistics": "No hay estadísticas disponibles",
    "system_press_esc_to_return": "Presiona ESC para volver",
    
    # Cheat Menu Buttons
    "cheat_close_instruction": "Presiona ESC o haz clic en X para cerrar",
    "cheat_press_esc_or_click": "Presiona ESC o haz clic en X para cerrar",
    "cheat_showing_items": "Mostrando",
    "cheat_scroll_up": "ARRIBA para desplazarse hacia arriba",
    "cheat_scroll_down": "ABAJO para desplazarse hacia abajo",
    "cheat_no_power_ups_selected": "Sin mejoras seleccionadas",
    
    # OS Task Manager / System Monitoring
    "os_running_processes": "PROCESOS EN EJECUCIÓN:",
    "os_no_active_processes": "Sin procesos activos",
    "os_process_name": "Nombre del Proceso",
    "os_version": "Versión",
    "os_status": "Estado",
    "os_system_performance": "DESEMPEÑO DEL SISTEMA:",
    "os_system_manager": "Administrador del Sistema",
    "os_system_paused": "Sistema pausado - presiona ESPACIO para continuar",
    "os_press_space_continue": "Presiona ESPACIO para continuar",
    
    # OS Desktop / System Info
    "os_system_monitor": "Monitor del Sistema",
    "os_cpu_idle": "CPU: Inactiva",
    "os_memory": "Memoria: 2.4 / 16 GB",
    "os_network": "Red: Conectada",
    "os_tophat_os": "TopHat-ShooterOS",
    "os_edition": "[Edición v5.1]",
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
    
    # Enemy Labels
    "enemy_active_threats": "AMENAZAS ACTIVAS:",
    
    # General
    "general_yes": "Sí",
    "general_no": "No",
    "general_back": "Volver",
    "general_confirm": "Confirmar",
    "general_cancel": "Cancelar"
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
