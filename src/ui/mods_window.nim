## MODS.EXE: the mod manager window.
##
## Installed: tick mods for this profile and Apply & Reload (the reload itself
## runs in main.nim, from the desktop, never mid-run). Game Modes: modes that
## loaded mods registered (launch/continue). Log: print output and errors.
## The banner states the one rule players must know: modded runs are cheated,
## unless every loaded mod opts out with "disableAchievements": false.

import std/[os, strutils, math]
import ../modding/mod_patch_core
import raylib, rlgl
import ../draw_prims
import os_window, ui_helpers, ../localization, ../render_context, ../save_system,
       ../gamepad_input, ../utils
import ui_theme
import ../modding/[mod_state, mod_catalog, mod_examples, mod_assets, mod_hooks, mod_registry]

type
  ModsTab* = enum
    mtInstalled, mtModes, mtCosmetics, mtApps, mtAchievements, mtLog, mtConsole

  ModsWindow* = ref object
    window*: OSWindow
    settings*: Settings
    tab*: ModsTab
    selected*: int
    listScroll*: int
    logScroll*: int
    logFollow*: bool
    achScroll*: int           ## the Achievements tab's scroll (px)
    lastLogGen: int
    pending*: seq[string]     ## working copy of settings.enabledMods
    message*: string          ## transient status line under the buttons
    messageTimer*: float32
    messageIsError*: bool
    modeRows*: seq[ModModeRow]
    modeSelected*: int
    launchRequest*: int       ## index into modeRows to launch, -1 = none
    launchResume*: bool
    cosScroll*: int
    appSelected*: int         ## register.app row highlighted in the Apps tab
    openAppRequest*: string   ## key of the app to open, "" = none (consumed by the window manager)
    removeTarget: string      ## folder the remove confirmation is about ("" = closed)
    removeName: string
    removeCooldown: float32   ## seconds until the confirmation's Remove unlocks
    applyConfirm: bool         ## pending Apply & Reload warning
    applyCooldown: float32
    updates: seq[tuple[folder, installed, shipped: string]]  ## examples Install Examples would update
    consoleInput*: string     ## the Console's line being typed (UTF-8)
    consoleHistory*: seq[string]
    consoleHistoryAt: int     ## the history entry Up/Down shows (len = the new line)

  ModModeRow* = object
    ## One mod game mode as the window shows it (filled by main.nim).
    name*, description*, modName*, baseName*: string
    canContinue*: bool

const
  ModsWindowW = 800
  ModsWindowH = 560
  TabH = 28
  TabW = 121
  AppRowH = 52
  AppHintH = 28  # the Apps tab's hint line, above its rows
  BannerH = 22
  ButtonH = 32
  ListW = 300
  RowH = 44
  CosRowH = 58
  AchRowH = 56
  RemoveBtnH = 28'f32
  RemoveConfirmCooldown = 1.5'f32  # anti-accident window, like the quit dialog
  ApplyConfirmCooldown = 1.0'f32
  LogLineH = 15
  ConsoleInputH = 26
  ConsoleMaxInput = 4000   # bytes of one entry

# The palette, drawn in the interface theme (ui_theme.nim).
template ColAccent: Color = uiInk(120, 220, 160)
template ColPanel: Color = uiSurface(12, 14, 20)
template ColRow: Color = uiSurface(22, 26, 36)
template ColRowSel: Color = uiSurface(28, 52, 44)
template ColText: Color = uiInk(225, 232, 240)
template ColMuted: Color = uiInk(145, 155, 170)
template ColOk: Color = uiInk(110, 230, 140)
template ColWarn: Color = uiInk(255, 190, 70)
template ColErr: Color = uiInk(255, 105, 95)

proc newModsWindow*(screenWidth, screenHeight: int, settings: Settings): ModsWindow {.moddable.} =
  let osWin = newOSWindow(t(tkModsWindowTitle),
                          (screenWidth - ModsWindowW) div 2, (screenHeight - ModsWindowH) div 2,
                          ModsWindowW, ModsWindowH, ColAccent, owtSettings, resizable = false)
  ModsWindow(window: osWin, settings: settings, logFollow: true, launchRequest: -1)

var modeRowsBuilder*: proc (): seq[ModModeRow] {.closure.}
  ## Installed by main.nim: the Game Modes rows (it knows the save files).

proc refreshModsWindow*(mw: ModsWindow) {.moddable.} =
  ## Re-read the enabled list (after a reload or a profile switch).
  mw.pending = mw.settings.enabledMods
  if not modeRowsBuilder.isNil:
    mw.modeRows = modeRowsBuilder()
  mw.updates = exampleUpdates()
  if installedMods.len == 0: mw.selected = 0
  else: mw.selected = clamp(mw.selected, 0, installedMods.high)

proc resetModsWindow*(mw: ModsWindow) {.moddable.} =
  ## On open: pick up folders dropped in since the last reload, and re-read the
  ## title so a language switch since startup shows up.
  mw.window.title = t(tkModsWindowTitle)
  rescanInstalledMods(mw.settings.enabledMods)
  mw.refreshModsWindow()
  mw.message = ""
  mw.applyConfirm = false
  mw.applyCooldown = 0

# ------------------------------------------------------------- geometry ----
type Geo = object
  x, y, w, h: int
  bodyY, bodyH: int
  list, detail, logArea: Rectangle
  consoleLog, consoleInput: Rectangle   ## the Console: the log over its input line
  tabs: array[ModsTab, Rectangle]
  applyBtn, folderBtn, examplesBtn, removeBtn: Rectangle
  confirm, confirmNo, confirmYes: Rectangle

proc geometry(mw: ModsWindow): Geo =
  result.x = mw.window.x + WINDOW_PADDING
  result.y = mw.window.y + TITLE_BAR_HEIGHT + WINDOW_PADDING
  result.w = mw.window.width - WINDOW_PADDING * 2
  result.h = mw.window.height - TITLE_BAR_HEIGHT - WINDOW_PADDING * 2
  let tabCount = ord(high(ModsTab)) + 1
  let tabW = min(TabW, (result.w - 6 * (tabCount - 1)) div tabCount)
  for tab in ModsTab:
    result.tabs[tab] = Rectangle(x: float32(result.x + ord(tab) * (tabW + 6)), y: result.y.float32,
                                 width: tabW.float32, height: TabH.float32)
  result.bodyY = result.y + TabH + 8 + BannerH + 8
  result.bodyH = result.y + result.h - ButtonH - 10 - result.bodyY
  result.list = Rectangle(x: result.x.float32, y: result.bodyY.float32,
                          width: ListW.float32, height: result.bodyH.float32)
  result.detail = Rectangle(x: float32(result.x + ListW + 12), y: result.bodyY.float32,
                            width: float32(result.w - ListW - 12), height: result.bodyH.float32)
  result.logArea = Rectangle(x: result.x.float32, y: result.bodyY.float32,
                             width: result.w.float32, height: result.bodyH.float32)
  result.consoleLog = Rectangle(x: result.x.float32, y: result.bodyY.float32, width: result.w.float32,
                                height: float32(result.bodyH - ConsoleInputH - 6))
  result.consoleInput = Rectangle(x: result.x.float32, y: float32(result.bodyY + result.bodyH - ConsoleInputH),
                                  width: result.w.float32, height: ConsoleInputH.float32)
  let by = float32(result.y + result.h - ButtonH)
  let applyW = max(170'i32, measureText(t(tkModsApply), 14) + 30).float32
  result.applyBtn = Rectangle(x: float32(result.x + result.w) - applyW, y: by,
                              width: applyW, height: ButtonH.float32)
  let folderW = max(130'i32, measureText(t(tkModsOpenFolder), 14) + 30).float32
  result.folderBtn = Rectangle(x: result.x.float32, y: by, width: folderW, height: ButtonH.float32)
  let exW = max(150'i32, measureText(t(tkModsInstallExamples), 14) + 30).float32
  result.examplesBtn = Rectangle(x: result.folderBtn.x + folderW + 8, y: by, width: exW,
                                 height: ButtonH.float32)
  let removeW = max(100'i32, measureText(t(tkModsRemove), 14) + 30).float32
  result.removeBtn = Rectangle(x: result.detail.x + result.detail.width - removeW - 12,
                               y: result.detail.y + result.detail.height - RemoveBtnH - 12,
                               width: removeW, height: RemoveBtnH)
  # the remove confirmation, centred on the window body
  const CW = 440.0'f32
  const CH = 190.0'f32
  const CBW = 150.0'f32
  const CBH = 36.0'f32
  let cx = float32(result.x) + (result.w.float32 - CW) / 2
  let cy = float32(result.y) + (result.h.float32 - CH) / 2
  result.confirm = Rectangle(x: cx, y: cy, width: CW, height: CH)
  let cby = cy + CH - CBH - 18
  result.confirmNo = Rectangle(x: cx + CW / 2 - CBW - 10, y: cby, width: CBW, height: CBH)
  result.confirmYes = Rectangle(x: cx + CW / 2 + 10, y: cby, width: CBW, height: CBH)

# ---------------------------------------------------------------- state ----
proc hasPendingChanges(mw: ModsWindow): bool =
  for id in mw.pending:
    if id notin mw.settings.enabledMods: return true
  for id in mw.settings.enabledMods:
    if id notin mw.pending: return true
  false

proc updateFor(mw: ModsWindow, m: ModInfo): string =
  ## The newer version this build ships of `m`, if `m` is an installed example
  ## (by folder, which is what Install Examples replaces); "" otherwise.
  if normalizedPath(parentDir(m.dir)) != normalizedPath(modsRootDir()): return ""
  let folder = lastPathPart(m.dir)
  for u in mw.updates:
    if u.folder == folder: return u.shipped
  ""

proc toggleable(m: ModInfo): bool = m.status notin {msInvalid, msDuplicate}

proc displayStatus(mw: ModsWindow, m: ModInfo): tuple[text: string, color: Color] =
  let want = m.id in mw.pending
  let applied = m.id in mw.settings.enabledMods
  case m.status
  of msInvalid: (t(tkModsStatusInvalid), ColErr)
  of msDuplicate: (t(tkModsStatusDuplicate), ColErr)
  of msLoaded:
    if want: (t(tkModsStatusLoaded), ColOk) else: (t(tkModsStatusWillUnload), ColWarn)
  of msError:
    if want and applied: (t(tkModsStatusError), ColErr)
    elif want: (t(tkModsStatusWillLoad), ColWarn)
    else: (t(tkModsStatusDisabled), ColMuted)
  of msMissingDep:
    if want and applied: (t(tkModsStatusMissingDep), ColErr)
    elif want: (t(tkModsStatusWillLoad), ColWarn)
    else: (t(tkModsStatusDisabled), ColMuted)
  of msDisabled:
    if want: (t(tkModsStatusWillLoad), ColWarn) else: (t(tkModsStatusDisabled), ColMuted)

proc toggle(mw: ModsWindow, i: int) =
  if i < 0 or i >= installedMods.len or not toggleable(installedMods[i]): return
  let id = installedMods[i].id
  let at = mw.pending.find(id)
  if at >= 0: mw.pending.delete(at)
  else: mw.pending.add(id)

proc pendingDisablesRewards(mw: ModsWindow): bool =
  for m in installedMods:
    if m.id in mw.pending and m.disableAchievements and
       m.status notin {msInvalid, msDuplicate}:
      return true
  false

proc apply(mw: ModsWindow) =
  mw.settings.enabledMods = mw.pending
  discard saveSettings(mw.settings)
  modReloadRequested = true

proc askApply(mw: ModsWindow) =
  if mw.pendingDisablesRewards():
    mw.applyConfirm = true
    mw.applyCooldown = ApplyConfirmCooldown
  else:
    mw.apply()

proc openFolder(path: string) =
  when defined(windows):
    discard execShellCmd("start \"\" \"" & path & "\"")
  else:
    discard execShellCmd("xdg-open \"" & path & "\" >/dev/null 2>&1 &")

proc say(mw: ModsWindow, text: string, isError = false) =
  mw.message = text
  mw.messageTimer = 6.0
  mw.messageIsError = isError

proc askRemove(mw: ModsWindow, i: int) =
  if i < 0 or i >= installedMods.len: return
  mw.removeTarget = installedMods[i].dir
  mw.removeName = installedMods[i].name
  mw.removeCooldown = RemoveConfirmCooldown

proc removeMod(mw: ModsWindow) =
  ## Delete the confirmed mod's folder. A mod that is running keeps running
  ## from memory, so it also triggers a reload to unload it.
  let dir = mw.removeTarget
  mw.removeTarget = ""
  var at = -1
  for i, m in installedMods:
    if m.dir == dir: at = i
  if at < 0: return
  let m = installedMods[at]
  # only ever a folder straight inside a mods folder (never a parent of one)
  var inModsFolder = false
  for root in modSearchDirs():
    if normalizedPath(parentDir(m.dir)) == normalizedPath(root): inModsFolder = true
  if not inModsFolder:
    mw.say(t(tkModsRemoveFailed), isError = true)
    return
  try:
    removeDir(m.dir)
  except IOError, OSError:
    rescanInstalledMods(mw.settings.enabledMods)
    mw.say(t(tkModsRemoveFailed), isError = true)
    return
  rescanInstalledMods(mw.settings.enabledMods)
  mw.updates = exampleUpdates()
  # Forget the id unless another folder still provides it (a duplicate).
  var idStillInstalled = false
  for other in installedMods:
    if other.id == m.id: idStillInstalled = true
  if not idStillInstalled:
    let p = mw.pending.find(m.id)
    if p >= 0: mw.pending.delete(p)
    let e = mw.settings.enabledMods.find(m.id)
    if e >= 0:
      mw.settings.enabledMods.delete(e)
      discard saveSettings(mw.settings)
  if m.status == msLoaded:
    modReloadRequested = true
  mw.selected = clamp(mw.selected, 0, max(0, installedMods.high))
  mw.say(t(tkModsRemoved).replace("$1", m.name))

proc logLines(): int = modLog.len

proc wantsTextInput*(mw: ModsWindow): bool {.moddable.} =
  ## The Console owns the keyboard while it is the tab in front.
  not mw.isNil and mw.window.visible and not mw.window.minimized and mw.window.focused and
    mw.tab == mtConsole

proc addConsoleChar(mw: ModsWindow, c: int32) =
  ## A typed character, as UTF-8 (the font draws Latin-1, U+0020..U+00FF).
  if c < 32 or c > 255 or c == 127 or mw.consoleInput.len >= ConsoleMaxInput: return
  if c < 128: mw.consoleInput.add(char(c))
  else:
    mw.consoleInput.add(char(0xC0 or (c shr 6)))
    mw.consoleInput.add(char(0x80 or (c and 0x3F)))

proc updateConsole(mw: ModsWindow) =
  ## Typing, Enter (run), Up / Down (history).
  var c = getCharPressed()
  while c > 0:
    mw.addConsoleChar(c)
    c = getCharPressed()
  if (isKeyPressed(KeyboardKey.Backspace) or isKeyPressedRepeat(KeyboardKey.Backspace)) and
     mw.consoleInput.len > 0:
    var n = mw.consoleInput.len - 1
    while n > 0 and (ord(mw.consoleInput[n]) and 0xC0) == 0x80: dec n   # a whole UTF-8 character
    mw.consoleInput.setLen(n)
  if isKeyPressed(KeyboardKey.Up) and mw.consoleHistoryAt > 0:
    dec mw.consoleHistoryAt
    mw.consoleInput = mw.consoleHistory[mw.consoleHistoryAt]
  elif isKeyPressed(KeyboardKey.Down) and mw.consoleHistoryAt < mw.consoleHistory.len:
    inc mw.consoleHistoryAt
    mw.consoleInput = if mw.consoleHistoryAt < mw.consoleHistory.len: mw.consoleHistory[mw.consoleHistoryAt]
                      else: ""
  if (isKeyPressed(KeyboardKey.Enter) or isKeyPressed(KeyboardKey.KpEnter)) and
     mw.consoleInput.strip.len > 0:
    let src = mw.consoleInput
    if mw.consoleHistory.len == 0 or mw.consoleHistory[^1] != src: mw.consoleHistory.add(src)
    mw.consoleHistoryAt = mw.consoleHistory.len
    mw.consoleInput = ""
    mw.logFollow = true
    runConsole(src)

# --------------------------------------------------------------- update ----
proc appOpenBtn(g: Geo, i: int): Rectangle =
  ## The Open button of Apps tab row `i` (rows sit under the one-line hint).
  Rectangle(x: float32(g.x + g.w - 124), y: float32(g.bodyY + AppHintH + i * AppRowH + 11),
            width: 110, height: 30)

proc updateModsWindow*(mw: ModsWindow, dt: float32, screenWidth, screenHeight: int,
                       allWindows: openArray[OSWindow]) {.moddable.} =
  updateOSWindow(mw.window, dt)
  if not mw.window.visible: return
  # Back cancels an open remove confirmation instead of closing the window.
  if mw.removeTarget.len > 0 and mw.window.focused and isBackPressed():
    mw.removeTarget = ""
    return
  if handleOSWindowInput(mw.window, screenWidth, screenHeight, allWindows):
    mw.window.visible = false
    mw.removeTarget = ""
    mw.applyConfirm = false
    return
  if mw.messageTimer > 0: mw.messageTimer -= dt
  if mw.window.minimized: return
  let g = mw.geometry()
  let mouse = getVirtualMousePosition()

  if mw.applyConfirm:
    if mw.applyCooldown > 0: mw.applyCooldown -= dt
    if mw.window.focused and isBackPressed():
      mw.applyConfirm = false
      return
    if mw.window.handledClickThisFrame and
       isWindowTopmostAtPoint(mw.window, mouse.x, mouse.y, allWindows):
      if checkCollisionPointRec(mouse, g.confirmNo):
        mw.applyConfirm = false
      elif checkCollisionPointRec(mouse, g.confirmYes) and mw.applyCooldown <= 0:
        mw.applyConfirm = false
        mw.apply()
    return

  # The remove confirmation is modal: it takes every click in the window.
  if mw.removeTarget.len > 0:
    if mw.removeCooldown > 0: mw.removeCooldown -= dt
    if mw.window.handledClickThisFrame and
       isWindowTopmostAtPoint(mw.window, mouse.x, mouse.y, allWindows):
      if checkCollisionPointRec(mouse, g.confirmNo):
        mw.removeTarget = ""
      elif checkCollisionPointRec(mouse, g.confirmYes) and mw.removeCooldown <= 0:
        mw.removeMod()
    return

  if mw.window.handledClickThisFrame and
     isWindowTopmostAtPoint(mw.window, mouse.x, mouse.y, allWindows):
    for tab in ModsTab:
      if checkCollisionPointRec(mouse, g.tabs[tab]):
        mw.tab = tab
    if mw.tab == mtInstalled:
      if checkCollisionPointRec(mouse, g.list):
        let row = (int(mouse.y - g.list.y) + mw.listScroll) div RowH
        if row >= 0 and row < installedMods.len:
          if mouse.x < g.list.x + 34:   # the checkbox column toggles
            mw.toggle(row)
          mw.selected = row
      if installedMods.len > 0 and checkCollisionPointRec(mouse, g.removeBtn):
        mw.askRemove(mw.selected)
      elif checkCollisionPointRec(mouse, g.applyBtn) and mw.hasPendingChanges():
        mw.askApply()
      elif checkCollisionPointRec(mouse, g.folderBtn):
        openFolder(modsRootDir())
      elif checkCollisionPointRec(mouse, g.examplesBtn):
        let (ok, written) = installExampleMods()
        if not ok:
          mw.say(t(tkModsExamplesFailed), isError = true)
        elif written.len == 0:
          mw.say(t(tkModsExamplesUpToDate))
        else:
          mw.say(t(tkModsExamplesInstalled))
        rescanInstalledMods(mw.settings.enabledMods)
        mw.updates = exampleUpdates()
        # An enabled example that was just replaced still runs the script it loaded
        # until the mods reload, so the game would go on playing the old version.
        for m in installedMods:
          if m.id in mw.settings.enabledMods and lastPathPart(m.dir) in written and
             normalizedPath(parentDir(m.dir)) == normalizedPath(modsRootDir()):
            modReloadRequested = true
    elif mw.tab == mtCosmetics:
      for i in 0 ..< modCosmetics.len:
        let ry = g.bodyY + i * CosRowH - mw.cosScroll
        let btn = Rectangle(x: float32(g.x + g.w - 124), y: float32(ry + 14), width: 110, height: 30)
        if ry + CosRowH > g.bodyY and ry < g.bodyY + g.bodyH and
           checkCollisionPointRec(mouse, btn):
          toggleCosmetic(i)
          mw.settings.modCosmetics = equippedEntries()
          discard saveSettings(mw.settings)
    elif mw.tab == mtApps:
      for i in 0 ..< modApps.len:
        if checkCollisionPointRec(mouse, appOpenBtn(g, i)):
          mw.appSelected = i
          mw.openAppRequest = modApps[i].key
    elif mw.tab == mtModes:
      for i in 0 ..< mw.modeRows.len:
        let rowY = g.bodyY + i * 64
        let launch = Rectangle(x: float32(g.x + g.w - 230), y: float32(rowY + 16), width: 110, height: 30)
        let cont = Rectangle(x: float32(g.x + g.w - 112), y: float32(rowY + 16), width: 110, height: 30)
        if checkCollisionPointRec(mouse, launch):
          mw.launchRequest = i
          mw.launchResume = false
        elif mw.modeRows[i].canContinue and checkCollisionPointRec(mouse, cont):
          mw.launchRequest = i
          mw.launchResume = true

  if mw.window.focused:
    if mw.tab == mtInstalled and installedMods.len > 0:
      var selectionMoved = false
      if isKeyPressed(KeyboardKey.Down) or gamepadNavPressed(gnDown):
        mw.selected = min(mw.selected + 1, installedMods.high)
        selectionMoved = true
      elif isKeyPressed(KeyboardKey.Up) or gamepadNavPressed(gnUp):
        mw.selected = max(mw.selected - 1, 0)
        selectionMoved = true
      elif isKeyPressed(KeyboardKey.Space):
        mw.toggle(mw.selected)
      # keep the selection in view
      if selectionMoved:
        let visible = max(1, int(g.list.height) div RowH)
        if mw.selected * RowH < mw.listScroll: mw.listScroll = mw.selected * RowH
        elif (mw.selected + 1) * RowH > mw.listScroll + visible * RowH:
          mw.listScroll = (mw.selected + 1) * RowH - visible * RowH
    if isKeyPressed(KeyboardKey.Tab):
      mw.tab = ModsTab((ord(mw.tab) + 1) mod (ord(high(ModsTab)) + 1))
  if mw.wantsTextInput(): mw.updateConsole()

  if mw.tab == mtApps and modApps.len > 0:
    mw.appSelected = clamp(mw.appSelected, 0, modApps.high)
    if mw.window.focused:
      if isKeyPressed(KeyboardKey.Down) or gamepadNavPressed(gnDown):
        mw.appSelected = min(mw.appSelected + 1, modApps.high)
      elif isKeyPressed(KeyboardKey.Up) or gamepadNavPressed(gnUp):
        mw.appSelected = max(mw.appSelected - 1, 0)
      elif isKeyPressed(KeyboardKey.Space) or isKeyPressed(KeyboardKey.Enter):
        mw.openAppRequest = modApps[mw.appSelected].key

  let wheel = getPointerWheelMove()
  case mw.tab
  of mtInstalled:
    let maxScroll = max(0, installedMods.len * RowH - int(g.list.height))
    if wheel != 0 and checkCollisionPointRec(mouse, g.list):
      mw.listScroll = mw.listScroll - int(wheel * RowH.float32)
    mw.listScroll = clamp(mw.listScroll, 0, maxScroll)
  of mtLog, mtConsole:
    let area = if mw.tab == mtLog: g.logArea else: g.consoleLog
    let maxScroll = max(0, logLines() * LogLineH - int(area.height) + 8)
    if wheel != 0 and checkCollisionPointRec(mouse, area):
      mw.logScroll = mw.logScroll - int(wheel * 3 * LogLineH.float32)
      mw.logFollow = mw.logScroll >= maxScroll
    if mw.logFollow:
      mw.logScroll = maxScroll
    mw.lastLogGen = modLogGeneration
    mw.logScroll = clamp(mw.logScroll, 0, maxScroll)
  of mtModes, mtApps:
    discard
  of mtAchievements:
    let maxScroll = max(0, advancementDefs.len * AchRowH - int(g.logArea.height))
    if wheel != 0 and checkCollisionPointRec(mouse, g.logArea):
      mw.achScroll = mw.achScroll - int(wheel * AchRowH.float32)
    mw.achScroll = clamp(mw.achScroll, 0, maxScroll)
  of mtCosmetics:
    let maxScroll = max(0, modCosmetics.len * CosRowH - int(g.logArea.height))
    if wheel != 0 and checkCollisionPointRec(mouse, g.logArea):
      mw.cosScroll = mw.cosScroll - int(wheel * CosRowH.float32)
    mw.cosScroll = clamp(mw.cosScroll, 0, maxScroll)

# ----------------------------------------------------------------- draw ----
proc drawButton(r: Rectangle, label: string, enabled, primary: bool) =
  let hovered = enabled and checkCollisionPointRec(getVirtualMousePosition(), r)
  let fill =
    if not enabled: uiSurface(30, 34, 42)
    elif primary: (if hovered: uiSurface(60, 150, 100) else: uiSurface(40, 120, 80))
    else: (if hovered: uiSurface(55, 62, 78) else: uiSurface(38, 44, 58))
  drawRectangle(r, fill)
  drawRectOutline(r, 1.0, if enabled: uiLine(150, 200, 175, 180) else: uiLine(70, 75, 85))
  let tw = measureText(label, 14)
  drawText(label, int32(r.x + (r.width - tw.float32) / 2), int32(r.y + (r.height - 14) / 2), 14,
           if enabled: ColText else: ColMuted)

proc drawRemoveButton(r: Rectangle, enabled: bool, label = "") =
  ## Red: the one destructive button in the window.
  let hovered = enabled and checkCollisionPointRec(getVirtualMousePosition(), r)
  let fill =
    if not enabled: uiSurface(60, 60, 64)
    elif hovered: uiSurface(158, 38, 38)
    else: uiSurface(118, 28, 28)
  drawRectangle(r, fill)
  drawRectOutline(r, 1.0, if enabled: uiLine(255, 100, 100, 220)
                             else: uiLine(110, 110, 115))
  let text = if label.len > 0: label else: t(tkModsRemove)
  let tw = measureText(text, 14)
  drawText(text, int32(r.x + (r.width - tw.float32) / 2), int32(r.y + (r.height - 14) / 2), 14,
           if enabled: ColText else: ColMuted)

proc drawCheckbox(x, y: int32, checked, enabled: bool) =
  let r = Rectangle(x: x.float32, y: y.float32, width: 16, height: 16)
  drawRectangle(r, uiSurface(8, 10, 14))
  drawRectOutline(r, 1.0, if enabled: ColAccent else: uiLine(70, 75, 85))
  if checked:
    drawRectangle(Rectangle(x: x.float32 + 4, y: y.float32 + 4, width: 8, height: 8), ColAccent)

proc hardWrap(text: string, maxW, size: int32): seq[string] =
  ## Word wrap, then split any word that is still too wide (folder paths,
  ## long identifiers) at character boundaries.
  for line in wrapTextLines(text, maxW, size):
    if measureText(line, size) <= maxW:
      result.add(line)
      continue
    var cur = ""
    for ch in line:
      if cur.len > 0 and measureText(cur & ch, size) > maxW:
        result.add(cur)
        cur = ""
      cur.add(ch)
    if cur.len > 0: result.add(cur)

proc drawWrapped(text: string, x, y, maxW, size: int32, color: Color, maxY: int32): int32 =
  ## Draw wrapped text from y; returns the y after the last line drawn.
  result = y
  for para in text.splitLines:
    for line in hardWrap(para, maxW, size):
      if result + size > maxY: return
      drawText(line, x, result, size, color)
      result += size + 3

proc drawRemoveConfirm(mw: ModsWindow, g: Geo) =
  ## Modal over the window body: which mod, that its folder goes, Cancel/Remove.
  drawRectangle(Rectangle(x: g.x.float32, y: float32(g.y), width: g.w.float32, height: g.h.float32),
                Color(r: 0, g: 0, b: 0, a: 150))
  let d = g.confirm
  drawRectangle(Rectangle(x: d.x + 6, y: d.y + 6, width: d.width, height: d.height), Color(r: 0, g: 0, b: 0, a: 140))
  drawRectangle(d, uiSurface(18, 22, 32))
  drawRectOutline(d, 2.0, uiLine(255, 80, 80))
  let tbH = 30'i32
  drawRectangle(Rectangle(x: d.x, y: d.y, width: d.width, height: tbH.float32), uiSurface(120, 28, 28))
  let title = t(tkModsRemoveTitle)
  drawText(title, int32(d.x + (d.width - measureText(title, 15).float32) / 2), int32(d.y) + 8, 15,
           uiInk(255, 200, 200))
  let x = int32(d.x) + 18
  let w = int32(d.width) - 36
  var y = int32(d.y) + tbH + 14
  let body = fitWithEllipsis(t(tkModsRemoveBody).replace("$1", mw.removeName), w, 16)
  drawText(body, int32(d.x + (d.width - measureText(body, 16).float32) / 2), y, 16, ColText)
  y += 24
  drawText(fitWithEllipsis(t(tkModsFolder) & " " & lastPathPart(mw.removeTarget), w, 12), x, y, 12, ColMuted)
  y += 18
  discard drawWrapped(t(tkModsRemoveSub), x, y, w, 12, uiInk(200, 150, 150),
                      int32(g.confirmNo.y) - 4)
  drawButton(g.confirmNo, t(tkConfirmCancelBtn), true, true)
  let ready = mw.removeCooldown <= 0
  drawRemoveButton(g.confirmYes, ready,
                   if ready: "" else: $int(ceil(mw.removeCooldown)))

proc drawApplyConfirm(mw: ModsWindow, g: Geo) =
  ## Warn before loading a mod set that disables player rewards.
  drawRectangle(Rectangle(x: g.x.float32, y: float32(g.y), width: g.w.float32, height: g.h.float32),
                Color(r: 0, g: 0, b: 0, a: 150))
  let d = g.confirm
  drawRectangle(Rectangle(x: d.x + 6, y: d.y + 6, width: d.width, height: d.height),
                Color(r: 0, g: 0, b: 0, a: 140))
  drawRectangle(d, uiSurface(18, 22, 32))
  drawRectOutline(d, 2.0, uiLine(255, 176, 32))
  let tbH = 30'i32
  drawRectangle(Rectangle(x: d.x, y: d.y, width: d.width, height: tbH.float32),
                uiSurface(120, 75, 18))
  let title = t(tkModsRewardsWarningTitle)
  drawText(title, int32(d.x + (d.width - measureText(title, 15).float32) / 2), int32(d.y) + 8, 15,
           uiInk(255, 225, 170))
  let x = int32(d.x) + 18
  let w = int32(d.width) - 36
  let bottom = int32(g.confirmNo.y) - 8
  var y = int32(d.y) + tbH + 14
  y = drawWrapped(t(tkModsRewardsWarningBody), x, y, w, 14, ColText, bottom)
  discard drawWrapped(t(tkModsRewardsWarningSub), x, y + 6, w, 12,
                      uiInk(255, 205, 120), bottom)
  drawButton(g.confirmNo, t(tkConfirmCancelBtn), true, false)
  let ready = mw.applyCooldown <= 0
  drawRemoveButton(g.confirmYes, ready,
                   if ready: t(tkModsRewardsWarningConfirm)
                   else: $int(ceil(mw.applyCooldown)))

proc drawInstalled(mw: ModsWindow, g: Geo) =
  if installedMods.len == 0:
    # No list and no detail pane: the message gets the whole body.
    let area = g.logArea
    drawRectangle(area, ColPanel)
    drawRectOutline(area, 1.0, uiLine(50, 60, 70))
    var y = int32(area.y) + 14
    let x = int32(area.x) + 12
    let w = int32(area.width) - 24
    let bottom = int32(area.y + area.height) - 6
    y = drawWrapped(t(tkModsEmpty), x, y, w, 13, ColText, bottom)
    y = drawWrapped(modsRootDir(), x + 8, y + 4, w - 8, 12, ColAccent, bottom)
    discard drawWrapped(t(tkModsEmptyHint), x, y + 8, w, 13, ColMuted, bottom)
  else:
    drawRectangle(g.list, ColPanel)
    drawRectOutline(g.list, 1.0, uiLine(50, 60, 70))
    beginVirtualScissorMode(int32(g.list.x), int32(g.list.y), int32(g.list.width), int32(g.list.height))
    for i, m in installedMods:
      let ry = int32(g.list.y) + int32(i * RowH - mw.listScroll)
      if ry + RowH < int32(g.list.y) or ry > int32(g.list.y + g.list.height): continue
      let rowRect = Rectangle(x: g.list.x + 2, y: ry.float32 + 2, width: g.list.width - 4, height: RowH - 4)
      drawRectangle(rowRect, if i == mw.selected: ColRowSel else: ColRow)
      drawCheckbox(int32(g.list.x) + 10, ry + 14, m.id in mw.pending, toggleable(m))
      drawText(fitWithEllipsis(m.name, int32(g.list.width) - 50, 14), int32(g.list.x) + 34, ry + 7, 14, ColText)
      let (st, col) = mw.displayStatus(m)
      let verSt = fitWithEllipsis(m.version & "  " & st, int32(g.list.width) - 50, 11)
      drawText(verSt, int32(g.list.x) + 34, ry + 26, 11, col)
      var tx = int32(g.list.x) + 34 + measureText(verSt, 11) + 10
      if mw.updateFor(m).len > 0:
        let tag = t(tkModsUpdateTag)
        if tx + measureText(tag, 10) < int32(g.list.x + g.list.width) - 6:
          drawText(tag, tx, ry + 27, 10, ColWarn)
          tx += measureText(tag, 10) + 10
      if m.status != msInvalid and not m.disableAchievements:
        let tag = t(tkModsKeepsTag)
        if tx + measureText(tag, 10) < int32(g.list.x + g.list.width) - 6:
          drawText(tag, tx, ry + 27, 10, ColOk)
    endVirtualScissorMode()

    # detail pane
    drawRectangle(g.detail, ColPanel)
    drawRectOutline(g.detail, 1.0, uiLine(50, 60, 70))
    if mw.selected >= 0 and mw.selected < installedMods.len:
      let m = installedMods[mw.selected]
      let x = int32(g.detail.x) + 14
      let w = int32(g.detail.width) - 28
      let bottom = int32(g.removeBtn.y) - 8   # the text stops above the Remove button
      var y = int32(g.detail.y) + 12
      drawText(fitWithEllipsis(m.name, w, 20), x, y, 20, ColText)
      y += 26
      var sub = m.id & "  v" & m.version
      if m.author.len > 0: sub.add("  " & t(tkModsBy) & " " & m.author)
      drawText(fitWithEllipsis(sub, w, 12), x, y, 12, ColMuted)
      y += 18
      let (st, col) = mw.displayStatus(m)
      drawText(st, x, y, 13, col)
      if m.status == msLoaded:
        # How much of each frame its scripts take (smoothed): mods are never
        # switched off for being slow, so this is how a player spots one.
        for rt in mods:
          if rt.id == m.id:
            let ms = t(tkModsFrameTime).replace("$1", formatFloat(rt.avgFrameMs, ffDecimal, 2))
            drawText(ms, x + measureText(st, 13) + 12, y + 1, 12, ColMuted)
      y += 20
      if m.status != msInvalid:
        drawText(fitWithEllipsis(t(if m.disableAchievements: tkModsRewardsOff else: tkModsRewardsKept), w, 12),
                 x, y, 12, if m.disableAchievements: ColWarn else: ColOk)
        y += 20
      if needsNewerGame(m):
        y = drawWrapped(t(tkModsNeedsNewerGame).replace("$1", m.game).replace("$2", GameVersion),
                        x, y, w, 12, ColWarn, bottom) + 6
      let update = mw.updateFor(m)
      if update.len > 0:
        y = drawWrapped(t(tkModsUpdateAvailable).replace("$1", update), x, y, w, 12, ColWarn, bottom) + 6
      if m.description.len > 0:
        y = drawWrapped(m.description, x, y, w, 13, ColText, bottom) + 6
      if m.dependencies.len > 0:
        y = drawWrapped(t(tkModsRequires) & " " & m.dependencies.join(", "), x, y, w, 12, ColMuted, bottom) + 4
      y = drawWrapped(t(tkModsFolder) & " " & m.dir, x, y, w, 11, ColMuted, bottom) + 4
      y = drawWrapped(t(tkModsFullAccess), x, y, w, 11, ColMuted, bottom) + 8
      if m.message.len > 0 and m.status != msLoaded:
        beginVirtualScissorMode(x, y, w, max(0'i32, bottom - y))
        discard drawWrapped(m.message, x, y, w, 11, ColErr, bottom)
        endVirtualScissorMode()
      drawRemoveButton(g.removeBtn, mw.removeTarget.len == 0)

  # button bar
  drawButton(g.folderBtn, t(tkModsOpenFolder), true, false)
  drawButton(g.examplesBtn, t(tkModsInstallExamples), true, mw.updates.len > 0)
  let pending = mw.hasPendingChanges()
  drawButton(g.applyBtn, t(tkModsApply), pending, true)
  if pending:
    let pt = t(tkModsPending)
    drawText(pt, int32(g.applyBtn.x) - measureText(pt, 12) - 10, int32(g.applyBtn.y) + 10, 12, ColWarn)
  elif mw.messageTimer > 0 and mw.message.len > 0:
    let maxW = int32(g.applyBtn.x - (g.examplesBtn.x + g.examplesBtn.width)) - 20
    drawText(fitWithEllipsis(mw.message, maxW, 12),
             int32(g.examplesBtn.x + g.examplesBtn.width) + 10, int32(g.applyBtn.y) + 10, 12,
             if mw.messageIsError: ColErr else: ColOk)

proc drawModes(mw: ModsWindow, g: Geo) =
  drawRectangle(g.logArea, ColPanel)
  drawRectOutline(g.logArea, 1.0, uiLine(50, 60, 70))
  if mw.modeRows.len == 0:
    discard drawWrapped(t(tkModsNoModes), int32(g.x) + 14, int32(g.bodyY) + 14, int32(g.w) - 28, 13,
                        ColMuted, int32(g.bodyY + g.bodyH))
    return
  for i, row in mw.modeRows:
    let y = int32(g.bodyY + i * 64)
    if y + 60 > int32(g.bodyY + g.bodyH): break
    drawRectangle(Rectangle(x: g.x.float32 + 2, y: y.float32 + 2, width: g.w.float32 - 4, height: 60), ColRow)
    let textW = int32(g.w) - 250
    drawText(fitWithEllipsis(row.name, textW, 16), int32(g.x) + 12, y + 8, 16, ColText)
    drawText(fitWithEllipsis(row.description, textW, 11), int32(g.x) + 12, y + 28, 11, ColMuted)
    drawText(fitWithEllipsis(t(tkModsBaseMode) & " " & row.baseName & "   " & t(tkModsFromMod) & " " & row.modName,
                             textW, 11), int32(g.x) + 12, y + 43, 11, ColMuted)
    drawButton(Rectangle(x: float32(g.x + g.w - 230), y: float32(y + 16), width: 110, height: 30),
               t(tkModsLaunch), true, true)
    drawButton(Rectangle(x: float32(g.x + g.w - 112), y: float32(y + 16), width: 110, height: 30),
               t(tkModsContinue), row.canContinue, false)

proc drawCosmetics(mw: ModsWindow, g: Geo) =
  drawRectangle(g.logArea, ColPanel)
  drawRectOutline(g.logArea, 1.0, uiLine(50, 60, 70))
  if modCosmetics.len == 0:
    discard drawWrapped(t(tkModsNoCosmetics), int32(g.x) + 14, int32(g.bodyY) + 14, int32(g.w) - 28, 13,
                        ColMuted, int32(g.bodyY + g.bodyH))
    return
  beginVirtualScissorMode(int32(g.logArea.x), int32(g.logArea.y), int32(g.logArea.width), int32(g.logArea.height))
  for i, c in modCosmetics:
    let ry = int32(g.bodyY + i * CosRowH - mw.cosScroll)
    if ry + CosRowH < int32(g.bodyY) or ry > int32(g.bodyY + g.bodyH): continue
    let equipped = equippedCosmetic[c.kind] == i + 1
    drawRectangle(Rectangle(x: g.x.float32 + 2, y: ry.float32 + 2, width: g.w.float32 - 4,
                            height: CosRowH - 4), if equipped: ColRowSel else: ColRow)
    # preview: the model (turning) or texture it draws with, else the palette
    # swatches. A desktop cosmetic shows its wallpaper over its cube model.
    let px = int32(g.x) + 10
    let py = ry + 7
    if c.look.model > 0 and (c.kind != mckDesktop or c.look.id == 0):
      drawModelIcon(c.look.model, px.float32 + 21, py.float32 + 21, 40, c.look.pose)
    elif c.look.id > 0:
      drawModTexture(c.look.id, px.float32 + 21, py.float32 + 21, 40, 40, 0, White)
    elif c.hasPalette:
      drawDisc(Vector2(x: px.float32 + 21, y: py.float32 + 21), 18, c.c1)
      drawDisc(Vector2(x: px.float32 + 21, y: py.float32 + 21), 11, c.c2)
      drawDisc(Vector2(x: px.float32 + 21, y: py.float32 + 21), 5, c.c3)
    let kindLabel = case c.kind
      of mckPlayer: t(tkModsKindPlayer)
      of mckBullet: t(tkModsKindBullet)
      of mckDesktop: t(tkModsKindDesktop)
      of mckCube: t(tkModsKindCube)
    let textX = px + 54
    let textW = int32(g.w) - 54 - 150
    drawText(fitWithEllipsis(c.name, textW, 15), textX, ry + 8, 15, ColText)
    drawText(fitWithEllipsis(kindLabel & "   " & c.key, textW, 11), textX, ry + 27, 11, ColAccent)
    if c.description.len > 0:
      drawText(fitWithEllipsis(c.description, textW, 11), textX, ry + 41, 11, ColMuted)
    drawButton(Rectangle(x: float32(g.x + g.w - 124), y: float32(ry + 14), width: 110, height: 30),
               (if equipped: t(tkModsUnequip) else: t(tkModsEquip)), true, not equipped)
  endVirtualScissorMode()

proc drawApps(mw: ModsWindow, g: Geo) =
  drawRectangle(g.logArea, ColPanel)
  drawRectOutline(g.logArea, 1.0, uiLine(50, 60, 70))
  if modApps.len == 0:
    discard drawWrapped(t(tkModsNoApps), int32(g.x) + 14, int32(g.bodyY) + 14,
                        int32(g.w) - 28, 13, ColMuted, int32(g.bodyY + g.bodyH))
    return
  let spanish = getLanguage() == Spanish
  discard drawWrapped(t(tkModsAppsHint), int32(g.x) + 14, int32(g.bodyY) + 8,
                      int32(g.w) - 28, 12, ColMuted, int32(g.bodyY + g.bodyH))
  for i in 0 ..< modApps.len:
    let btn = appOpenBtn(g, i)
    if btn.y + btn.height > g.logArea.y + g.logArea.height: break
    let ry = int32(btn.y) - 11
    drawRectangle(Rectangle(x: g.logArea.x + 4, y: ry.float32, width: g.logArea.width - 8,
                            height: AppRowH - 4), if i == mw.appSelected: ColRowSel else: ColRow)
    drawRectangle(Rectangle(x: g.logArea.x + 4, y: ry.float32, width: 4, height: AppRowH - 4),
                  modApps[i].color)
    let textW = int32(g.logArea.width) - 40 - int32(btn.width)
    drawText(fitWithEllipsis(modAppName(i, spanish), textW, 15),
             int32(g.logArea.x) + 20, ry + 8, 15, ColText)
    drawText(fitWithEllipsis(modApps[i].key.split(':')[0] &
                             (if modApps[i].desktop: "" else: "   " & t(tkModsAppNoIcon)), textW, 11),
             int32(g.logArea.x) + 20, ry + 28, 11, ColMuted)
    drawButton(btn, t(tkModsOpenApp), true, true)

proc drawAchievements(mw: ModsWindow, g: Geo) =
  ## The loaded mods' own achievements (register.advancement), this profile's
  ## progress. They never touch the game's own advancements or rewards.
  drawRectangle(g.logArea, ColPanel)
  drawRectOutline(g.logArea, 1.0, uiLine(50, 60, 70))
  if advancementDefs.len == 0:
    discard drawWrapped(t(tkModsNoAchievements), int32(g.x) + 14, int32(g.bodyY) + 14,
                        int32(g.w) - 28, 13, ColMuted, int32(g.bodyY + g.bodyH))
    return
  beginVirtualScissorMode(int32(g.logArea.x), int32(g.logArea.y), int32(g.logArea.width), int32(g.logArea.height))
  for i in 0 ..< advancementDefs.len:
    let d = advancementDefs[i]
    let ry = int32(g.logArea.y) + 4 + int32(i * AchRowH - mw.achScroll)
    if ry + AchRowH < int32(g.logArea.y) or ry > int32(g.logArea.y + g.logArea.height): continue
    let st = advancementState(d.key)
    let shown = st.unlocked or not d.hidden
    drawRectangle(Rectangle(x: g.logArea.x + 4, y: ry.float32, width: g.logArea.width - 8,
                            height: AchRowH - 4), ColRow)
    let accent = uiInk(if st.unlocked: d.color else: Color(r: 90, g: 98, b: 112, a: 255))
    drawRectangle(Rectangle(x: g.logArea.x + 4, y: ry.float32, width: 4, height: AchRowH - 4), accent)
    let ix = int32(g.logArea.x) + 16
    if d.iconTex > 0 and shown:
      drawModTexture(d.iconTex, ix.float32 + 16, ry.float32 + 22, 32, 32, 0,
                     if st.unlocked: White else: Color(r: 120, g: 120, b: 120, a: 255))
    else:
      drawCircleOutline(ix + 16, ry + 22, 14, accent)
      drawText(if st.unlocked: "*" else: "?", ix + 12, ry + 14, 18, accent)
    let textX = ix + 44
    let textW = int32(g.logArea.width) - 44 - 200
    drawText(fitWithEllipsis(if shown: advancementName(i) else: "???", textW, 15), textX, ry + 6, 15,
             if st.unlocked: ColText else: ColMuted)
    let desc = if shown: advancementDescription(i) else: t(tkModsHiddenAchievement)
    drawText(fitWithEllipsis(desc, textW, 11), textX, ry + 25, 11, ColMuted)
    drawText(fitWithEllipsis(d.key.split(':')[0], textW, 10), textX, ry + 39, 10, ColAccent)
    # progress
    let bx = int32(g.logArea.x + g.logArea.width) - 180
    if st.unlocked:
      drawText(t(tkModsAchievementDone) & (if st.unlockedAt.len > 0: "  " & st.unlockedAt else: ""),
               bx, ry + 18, 12, ColOk)
    else:
      let frac = clamp(st.progress.float32 / max(1, d.goal).float32, 0'f32, 1'f32)
      drawRectangle(bx, ry + 20, 160, 8, uiSurface(20, 26, 36))
      drawRectangle(bx, ry + 20, int32(160 * frac), 8, d.color)
      drawText($st.progress & " / " & $d.goal, bx, ry + 32, 10, ColMuted)
  endVirtualScissorMode()

proc drawLog(mw: ModsWindow, g: Geo, area: Rectangle) =
  drawRectangle(area, ColPanel)
  drawRectOutline(area, 1.0, uiLine(50, 60, 70))
  if modLog.len == 0:
    drawText(t(tkModsLogEmpty), int32(g.x) + 12, int32(g.bodyY) + 12, 13, ColMuted)
    return
  beginVirtualScissorMode(int32(area.x), int32(area.y), int32(area.width), int32(area.height))
  let maxW = int32(area.width) - 20
  for i, line in modLog:
    let y = int32(area.y) + 6 + int32(i * LogLineH - mw.logScroll)
    if y + LogLineH < int32(area.y) or y > int32(area.y + area.height): continue
    let prefix = if line.modId.len > 0: "[" & line.modId & "] " else: ""
    let col = case line.level
      of mlInfo: ColText
      of mlWarn: ColWarn
      of mlError: ColErr
    drawText(fitWithEllipsis(prefix & line.text, maxW, 11), int32(area.x) + 10, y, 11, col)
  endVirtualScissorMode()

proc drawConsole(mw: ModsWindow, g: Geo) =
  ## The log, and under it the line being typed (its end, when it is long).
  mw.drawLog(g, g.consoleLog)
  let r = g.consoleInput
  drawRectangle(r, uiSurface(16, 20, 28))
  drawRectOutline(r, 1.0, if mw.window.focused: ColAccent else: uiLine(70, 78, 92))
  let x = int32(r.x) + 8
  let y = int32(r.y) + 7
  let room = int32(r.width) - 30
  let tx = x + 14
  drawText(">", x, y, 12, ColAccent)
  if mw.consoleInput.len == 0:
    drawText(fitWithEllipsis(t(tkModsConsoleHint), room, 12), tx, y, 12, ColMuted)
  var shown = mw.consoleInput
  while shown.len > 0 and measureText(shown, 12) > room:   # keep the end (the caret) in view
    var n = 1
    while n < shown.len and (ord(shown[n]) and 0xC0) == 0x80: inc n
    shown = shown[n .. ^1]
  if shown.len > 0: drawText(shown, tx, y, 12, ColText)
  if mw.window.focused and int(getTime() * 2.0) mod 2 == 0:   # the caret
    let cx = tx + (if shown.len > 0: measureText(shown, 12) + 1 else: 0)
    drawRectangle(cx, y - 1, 2, 14, ColText)

proc drawModsWindow*(mw: ModsWindow) {.moddable.} =
  if not mw.window.visible: return
  drawWindowChrome(mw.window)
  if mw.window.minimized: return
  let g = mw.geometry()

  # tabs
  let labels: array[ModsTab, string] = [t(tkModsTabInstalled), t(tkModsTabModes),
                                        t(tkModsTabCosmetics), t(tkModsTabApps),
                                        t(tkModsTabAchievements), t(tkModsTabLog),
                                        t(tkModsTabConsole)]
  for tab in ModsTab:
    let r = g.tabs[tab]
    let active = mw.tab == tab
    drawRectangle(r, if active: uiSurface(30, 70, 55) else: uiSurface(28, 32, 42))
    drawRectOutline(r, 1.0, if active: ColAccent else: uiLine(70, 78, 92))
    let size = bestFitFontSize(labels[tab], int32(r.width) - 12, 14, 10)   # (7 tabs: narrow ones)
    let tw = measureText(labels[tab], size)
    drawText(labels[tab], int32(r.x + (r.width - tw.float32) / 2), int32(r.y) + (TabH - size) div 2, size,
             if active: ColText else: ColMuted)

  # the rule players must know
  let banner = Rectangle(x: g.x.float32, y: float32(g.y + TabH + 8), width: g.w.float32, height: BannerH.float32)
  let keeps = modsActive and not modsDisableAchievements   # every loaded mod keeps rewards
  let bannerText = t(if keeps: tkModsKeepsBanner else: tkModsCheatBanner)
  drawRectangle(banner, if keeps: uiSurface(12, 42, 30) else: uiSurface(48, 34, 8))
  drawRectOutline(banner, 1.0, if keeps: uiLine(60, 200, 140, 200)
                                  else: uiLine(255, 176, 32, 200))
  let bannerSize = bestFitFontSize(bannerText, int32(g.w) - 16, 12, 10)
  drawText(fitWithEllipsis(bannerText, int32(g.w) - 16, bannerSize),
           int32(g.x) + 8, int32(banner.y) + (BannerH - bannerSize) div 2, bannerSize,
           if keeps: ColOk else: ColWarn)

  case mw.tab
  of mtInstalled: mw.drawInstalled(g)
  of mtModes: mw.drawModes(g)
  of mtCosmetics: mw.drawCosmetics(g)
  of mtApps: mw.drawApps(g)
  of mtAchievements: mw.drawAchievements(g)
  of mtLog: mw.drawLog(g, g.logArea)
  of mtConsole: mw.drawConsole(g)

  if mw.removeTarget.len > 0:
    mw.drawRemoveConfirm(g)
  elif mw.applyConfirm:
    mw.drawApplyConfirm(g)
