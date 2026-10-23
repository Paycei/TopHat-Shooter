## A co-op run's progress for this machine's own profile. The host records
## what its teammates earn (coop_context.ProfileEvent: banked shards, the
## codex, unlocks, advancements, roguelite records) and sends it; a client
## applies it here, to its own profile, exactly as the host applied its own
## where it was earned. Rewards in co-op are each player's own.

import ../modding/mod_patch_core
import ../types, ../settings, ../save_system, ../statistics, ../roguelite, ../powerup_data,
       ../advancement, ../localization
import coop_context

proc applyProfileEvent*(ev: ProfileEvent, advProfile: AdvancementProfile): string {.moddable.} =
  ## Apply one event to this machine's profile. Returns a toast to show ("" =
  ## none).
  case ev.kind
  of pekMetaBank:
    discard bankMetaCurrency(ev.a.int, ev.b.int)
  of pekRecursion:
    let profile = activeRogueliteProfile
    if not profile.isNil:
      profile.recursionDamageBonus += recursionDamageBonusForLevel(ev.a.int)
      profile.recursionLevel = max(profile.recursionLevel, ev.a.int)
      discard saveRogueliteProfile(profile)
  of pekDiscovered:
    if not globalSettings.isNil and ev.text.len > 0 and
       ev.text notin globalSettings.discoveredPowerUps:
      globalSettings.discoveredPowerUps.add(ev.text)
      discard saveSettings(globalSettings)
      result = t(tkNewProcessInstalled)
  of pekBossDefeated:
    if not globalStats.isNil and ev.a > 0 and not globalStats.hasDefeatedBoss(ev.a.int):
      globalStats.markBossDefeated(ev.a.int)
      discard saveStatistics(globalStats)
  of pekUnlock:
    if globalSettings.isNil: return
    case ev.text
    of "tophat":
      if not globalSettings.kernelTophatUnlocked:
        globalSettings.kernelTophatUnlocked = true
        globalSettings.kernelTophatEquipped = true
        globalSettings.cheaterHatEquipped = false
        discard saveSettings(globalSettings)
    of "roguelite":
      if not globalSettings.rogueliteUnlocked:
        globalSettings.rogueliteUnlocked = true
        discard saveSettings(globalSettings)
        result = t(tkGameModeUnlocked) & " " & t(tkRogueliteUnlockedNotif)
    of "survival":
      if not globalSettings.survivalUnlocked:
        globalSettings.survivalUnlocked = true
        discard saveSettings(globalSettings)
        result = t(tkGameModeUnlocked) & " " & t(tkSurvivalUnlockedNotif)
    else: discard
  of pekAdvancement:
    if not advProfile.isNil and ev.text.len > 0 and
       unlockAdvancementDirectly(advProfile, ev.text):
      discard saveAdvancements(advProfile)
  of pekRogueliteBank:
    let profile = activeRogueliteProfile
    if not profile.isNil:
      if ev.flag: profile.totalRuns += 1
      profile.dataShards += max(0, ev.a.int)
      profile.cores += max(0, ev.b.int)
      profile.bestFloor = max(profile.bestFloor, ev.c.int)
      profile.bestRooms = max(profile.bestRooms, ev.d.int)
      profile.bestEndlessLoop = max(profile.bestEndlessLoop, ev.e.int)
      discard saveRogueliteProfile(profile)
  of pekRogueliteWin:
    let profile = activeRogueliteProfile
    if not profile.isNil:
      profile.wins += 1
      profile.bestEndlessLoop = max(profile.bestEndlessLoop, ev.e.int)
      # Heat is earned: winning at your own highest Heat unlocks the next one.
      if ev.c.int >= profile.highestHeat and profile.highestHeat < RogueliteMaxHeat:
        inc profile.highestHeat
      discard saveRogueliteProfile(profile)
