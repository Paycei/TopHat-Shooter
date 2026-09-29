## MODS.EXE: the mod manager window.
##
## Installed: tick mods for this profile and Apply & Reload (the reload itself
## runs in main.nim, from the desktop, never mid-run). Game Modes: modes that
## loaded mods registered (launch/continue). Log: print output and errors.
## The banner states the one rule players must know: modded runs are cheated,
## unless every loaded mod opts out with "disableAchievements": false.

import std/[os, strutils, math]
import raylib, rlgl
import os_window, ui_helpers, ../localization, ../render_context, ../save_system,
       ../gamepad_input
import ../modding/[mod_state, mod_catalog, mod_examples, mod_assets, mod_hooks]

type
  ModsTab* = enum
    mtInstalled, mtModes, mtCosmetics, mtApps, mtLog

  ModsWindow* = ref object
    window*: OSWindow
    settings*: Settings
    tab*: ModsTab
    selected*: int
    listScroll*: int
    logScroll*: int
    logFollow*: bool
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

  ModModeRow* = object
    ## One mod game mode as the window shows it (filled by main.nim).
    name*, description*, modName*, baseName*: string
    canContinue*: bool

const
  ModsWindowW = 800
  ModsWindowH = 560
  TabH = 28
  TabW = 146
  AppRowH = 52
  AppHintH = 28  # the Apps tab's hint line, above its rows
  BannerH = 22
  ButtonH = 32
  ListW = 300
  RowH = 44
  CosRowH = 58
  RemoveBtnH = 28'f32
  RemoveConfirmCooldown = 1.5'f32  # anti-accident window, like the quit dialog
  LogLineH = 15

  ColAccent = Color(r: 120, g: 220, b: 160, a: 255)
  ColPanel = Color(r: 12, g: 14, b: 20, a: 255)
  ColRow = Color(r: 22, g: 26, b: 36, a: 255)
  ColRowSel = Color(r: 28, g: 52, b: 44, a: 255)
  ColText = Color(r: 225, g: 232, b: 240, a: 255)
  ColMuted = Color(r: 145, g: 155, b: 170, a: 255)
  ColOk = Color(r: 110, g: 230, b: 140, a: 255)
  ColWarn = Color(r: 255, g: 190, b: 70, a: 255)
  ColErr = Color(r: 255, g: 105, b: 95, a: 255)

proc newModsWindow*(screenWidth, screenHeight: int, settings: Settings): ModsWindow =
  let osWin = newOSWindow(t(tkModsWindowTitle),
                          (screenWidth - ModsWindowW) div 2, (screenHeight - ModsWindowH) div 2,
                          ModsWindowW, ModsWindowH, ColAccent, owtSettings, resizable = false)
  ModsWindow(window: osWin, settings: settings, logFollow: true, launchRequest: -1)

var modeRowsBuilder*: proc (): seq[ModModeRow] {.closure.}
  ## Installed by main.nim: the Game Modes rows (it knows the save files).

proc refreshModsWindow*(mw: ModsWindow) =
  ## Re-read the enabled list (after a reload or a profile switch).
  mw.pending = mw.settings.enabledMods
  if not modeRowsBuilder.isNil:
    mw.modeRows = modeRowsBuilder()
  if installedMods.len == 0: mw.selected = 0
  else: mw.selected = clamp(mw.selected, 0, installedMods.high)

proc resetModsWindow*(mw: ModsWindow) =
  ## On open: pick up folders dropped in since the last reload, and re-read the
  ## title so a language switch since startup shows up.
  mw.window.title = t(tkModsWindowTitle)
  rescanInstalledMods(mw.settings.enabledMods)
  mw.refreshModsWindow()
  mw.message = ""

# ------------------------------------------------------------- geometry ----
type Geo = object
  x, y, w, h: int
  bodyY, bodyH: int
  list, detail, logArea: Rectangle
  tabs: array[ModsTab, Rectangle]
  applyBtn, folderBtn, examplesBtn, removeBtn: Rectangle
  confirm, confirmNo, confirmYes: Rectangle

proc geometry(mw: ModsWindow): Geo =
  result.x = mw.window.x + WINDOW_PADDING
  result.y = mw.window.y + TITLE_BAR_HEIGHT + WINDOW_PADDING
  result.w = mw.window.width - WINDOW_PADDING * 2
  result.h = mw.window.height - TITLE_BAR_HEIGHT - WINDOW_PADDING * 2
  for tab in ModsTab:
    result.tabs[tab] = Rectangle(x: float32(result.x + ord(tab) * (TabW + 6)), y: result.y.float32,
                                 width: TabW.float32, height: TabH.float32)
  result.bodyY = result.y + TabH + 8 + BannerH + 8
  result.bodyH = result.y + result.h - ButtonH - 10 - result.bodyY
  result.list = Rectangle(x: result.x.float32, y: result.bodyY.float32,
                          width: ListW.float32, height: result.bodyH.float32)
  result.detail = Rectangle(x: float32(result.x + ListW + 12), y: result.bodyY.float32,
                            width: float32(result.w - ListW - 12), height: result.bodyH.float32)
  result.logArea = Rectangle(x: result.x.float32, y: result.bodyY.float32,
                             width: result.w.float32, height: result.bodyH.float32)
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

proc apply(mw: ModsWindow) =
  mw.settings.enabledMods = mw.pending
  discard saveSettings(mw.settings)
  modReloadRequested = true

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

# --------------------------------------------------------------- update ----
proc appOpenBtn(g: Geo, i: int): Rectangle =
  ## The Open button of Apps tab row `i` (rows sit under the one-line hint).
  Rectangle(x: float32(g.x + g.w - 124), y: float32(g.bodyY + AppHintH + i * AppRowH + 11),
            width: 110, height: 30)

proc updateModsWindow*(mw: ModsWindow, dt: float32, screenWidth, screenHeight: int,
                       allWindows: openArray[OSWindow]) =
  updateOSWindow(mw.window, dt)
  if not mw.window.visible: return
  # Back cancels an open remove confirmation instead of closing the window.
  if mw.removeTarget.len > 0 and mw.window.focused and isBackPressed():
    mw.removeTarget = ""
    return
  if handleOSWindowInput(mw.window, screenWidth, screenHeight, allWindows):
    mw.window.visible = false
    mw.removeTarget = ""
    return
  if mw.messageTimer > 0: mw.messageTimer -= dt
  if mw.window.minimized: return
  let g = mw.geometry()
  let mouse = getVirtualMousePosition()

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
        mw.apply()
      elif checkCollisionPointRec(mouse, g.folderBtn):
        openFolder(modsRootDir())
      elif checkCollisionPointRec(mouse, g.examplesBtn):
        let (ok, written) = installExampleMods()
        if not ok:
          mw.say(t(tkModsExamplesFailed), isError = true)
        elif written == 0:
          mw.say(t(tkModsExamplesUpToDate))
        else:
          mw.say(t(tkModsExamplesInstalled))
        rescanInstalledMods(mw.settings.enabledMods)
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
      if isKeyPressed(KeyboardKey.Down) or gamepadNavPressed(gnDown):
        mw.selected = min(mw.selected + 1, installedMods.high)
      elif isKeyPressed(KeyboardKey.Up) or gamepadNavPressed(gnUp):
        mw.selected = max(mw.selected - 1, 0)
      elif isKeyPressed(KeyboardKey.Space):
        mw.toggle(mw.selected)
      # keep the selection in view
      let visible = max(1, int(g.list.height) div RowH)
      if mw.selected * RowH < mw.listScroll: mw.listScroll = mw.selected * RowH
      elif (mw.selected + 1) * RowH > mw.listScroll + visible * RowH:
        mw.listScroll = (mw.selected + 1) * RowH - visible * RowH
    if isKeyPressed(KeyboardKey.Tab):
      mw.tab = ModsTab((ord(mw.tab) + 1) mod (ord(high(ModsTab)) + 1))

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
  of mtLog:
    let maxScroll = max(0, logLines() * LogLineH - int(g.logArea.height) + 8)
    if wheel != 0 and checkCollisionPointRec(mouse, g.logArea):
      mw.logScroll = mw.logScroll - int(wheel * 3 * LogLineH.float32)
      mw.logFollow = mw.logScroll >= maxScroll
    if mw.logFollow:
      mw.logScroll = maxScroll
    mw.lastLogGen = modLogGeneration
    mw.logScroll = clamp(mw.logScroll, 0, maxScroll)
  of mtModes, mtApps:
    discard
  of mtCosmetics:
    let maxScroll = max(0, modCosmetics.len * CosRowH - int(g.logArea.height))
    if wheel != 0 and checkCollisionPointRec(mouse, g.logArea):
      mw.cosScroll = mw.cosScroll - int(wheel * CosRowH.float32)
    mw.cosScroll = clamp(mw.cosScroll, 0, maxScroll)

# ----------------------------------------------------------------- draw ----
proc drawButton(r: Rectangle, label: string, enabled, primary: bool) =
  let hovered = enabled and checkCollisionPointRec(getVirtualMousePosition(), r)
  let fill =
    if not enabled: Color(r: 30, g: 34, b: 42, a: 255)
    elif primary: (if hovered: Color(r: 60, g: 150, b: 100, a: 255) else: Color(r: 40, g: 120, b: 80, a: 255))
    else: (if hovered: Color(r: 55, g: 62, b: 78, a: 255) else: Color(r: 38, g: 44, b: 58, a: 255))
  drawRectangle(r, fill)
  drawRectangleLines(r, 1.0, if enabled: Color(r: 150, g: 200, b: 175, a: 180) else: Color(r: 70, g: 75, b: 85, a: 255))
  let tw = measureText(label, 14)
  drawText(label, int32(r.x + (r.width - tw.float32) / 2), int32(r.y + (r.height - 14) / 2), 14,
           if enabled: ColText else: ColMuted)

proc drawRemoveButton(r: Rectangle, enabled: bool, label = "") =
  ## Red: the one destructive button in the window.
  let hovered = enabled and checkCollisionPointRec(getVirtualMousePosition(), r)
  let fill =
    if not enabled: Color(r: 60, g: 60, b: 64, a: 255)
    elif hovered: Color(r: 158, g: 38, b: 38, a: 255)
    else: Color(r: 118, g: 28, b: 28, a: 255)
  drawRectangle(r, fill)
  drawRectangleLines(r, 1.0, if enabled: Color(r: 255, g: 100, b: 100, a: 220)
                             else: Color(r: 110, g: 110, b: 115, a: 255))
  let text = if label.len > 0: label else: t(tkModsRemove)
  let tw = measureText(text, 14)
  drawText(text, int32(r.x + (r.width - tw.float32) / 2), int32(r.y + (r.height - 14) / 2), 14,
           if enabled: ColText else: ColMuted)

proc drawCheckbox(x, y: int32, checked, enabled: bool) =
  let r = Rectangle(x: x.float32, y: y.float32, width: 16, height: 16)
  drawRectangle(r, Color(r: 8, g: 10, b: 14, a: 255))
  drawRectangleLines(r, 1.0, if enabled: ColAccent else: Color(r: 70, g: 75, b: 85, a: 255))
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
  drawRectangle(d, Color(r: 18, g: 22, b: 32, a: 255))
  drawRectangleLines(d, 2.0, Color(r: 255, g: 80, b: 80, a: 255))
  let tbH = 30'i32
  drawRectangle(Rectangle(x: d.x, y: d.y, width: d.width, height: tbH.float32), Color(r: 120, g: 28, b: 28, a: 255))
  let title = t(tkModsRemoveTitle)
  drawText(title, int32(d.x + (d.width - measureText(title, 15).float32) / 2), int32(d.y) + 8, 15,
           Color(r: 255, g: 200, b: 200, a: 255))
  let x = int32(d.x) + 18
  let w = int32(d.width) - 36
  var y = int32(d.y) + tbH + 14
  let body = fitWithEllipsis(t(tkModsRemoveBody).replace("$1", mw.removeName), w, 16)
  drawText(body, int32(d.x + (d.width - measureText(body, 16).float32) / 2), y, 16, ColText)
  y += 24
  drawText(fitWithEllipsis(t(tkModsFolder) & " " & lastPathPart(mw.removeTarget), w, 12), x, y, 12, ColMuted)
  y += 18
  discard drawWrapped(t(tkModsRemoveSub), x, y, w, 12, Color(r: 200, g: 150, b: 150, a: 255),
                      int32(g.confirmNo.y) - 4)
  drawButton(g.confirmNo, t(tkConfirmCancelBtn), true, true)
  let ready = mw.removeCooldown <= 0
  drawRemoveButton(g.confirmYes, ready,
                   if ready: "" else: $int(ceil(mw.removeCooldown)))

proc drawInstalled(mw: ModsWindow, g: Geo) =
  if installedMods.len == 0:
    # No list and no detail pane: the message gets the whole body.
    let area = g.logArea
    drawRectangle(area, ColPanel)
    drawRectangleLines(area, 1.0, Color(r: 50, g: 60, b: 70, a: 255))
    var y = int32(area.y) + 14
    let x = int32(area.x) + 12
    let w = int32(area.width) - 24
    let bottom = int32(area.y + area.height) - 6
    y = drawWrapped(t(tkModsEmpty), x, y, w, 13, ColText, bottom)
    y = drawWrapped(modsRootDir(), x + 8, y + 4, w - 8, 12, ColAccent, bottom)
    discard drawWrapped(t(tkModsEmptyHint), x, y + 8, w, 13, ColMuted, bottom)
  else:
    drawRectangle(g.list, ColPanel)
    drawRectangleLines(g.list, 1.0, Color(r: 50, g: 60, b: 70, a: 255))
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
      if m.status != msInvalid and not m.disableAchievements:
        let tag = t(tkModsKeepsTag)
        let tx = int32(g.list.x) + 34 + measureText(verSt, 11) + 10
        if tx + measureText(tag, 10) < int32(g.list.x + g.list.width) - 6:
          drawText(tag, tx, ry + 27, 10, ColOk)
    endScissorMode()

    # detail pane
    drawRectangle(g.detail, ColPanel)
    drawRectangleLines(g.detail, 1.0, Color(r: 50, g: 60, b: 70, a: 255))
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
      y += 20
      if m.status != msInvalid:
        drawText(fitWithEllipsis(t(if m.disableAchievements: tkModsRewardsOff else: tkModsRewardsKept), w, 12),
                 x, y, 12, if m.disableAchievements: ColWarn else: ColOk)
        y += 20
      if m.description.len > 0:
        y = drawWrapped(m.description, x, y, w, 13, ColText, bottom) + 6
      if m.dependencies.len > 0:
        y = drawWrapped(t(tkModsRequires) & " " & m.dependencies.join(", "), x, y, w, 12, ColMuted, bottom) + 4
      y = drawWrapped(t(tkModsFolder) & " " & m.dir, x, y, w, 11, ColMuted, bottom) + 8
      if m.message.len > 0 and m.status != msLoaded:
        beginVirtualScissorMode(x, y, w, max(0'i32, bottom - y))
        discard drawWrapped(m.message, x, y, w, 11, ColErr, bottom)
        endScissorMode()
      drawRemoveButton(g.removeBtn, mw.removeTarget.len == 0)

  # button bar
  drawButton(g.folderBtn, t(tkModsOpenFolder), true, false)
  drawButton(g.examplesBtn, t(tkModsInstallExamples), true, false)
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
  drawRectangleLines(g.logArea, 1.0, Color(r: 50, g: 60, b: 70, a: 255))
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
  drawRectangleLines(g.logArea, 1.0, Color(r: 50, g: 60, b: 70, a: 255))
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
      drawCircle(Vector2(x: px.float32 + 21, y: py.float32 + 21), 18, c.c1)
      drawCircle(Vector2(x: px.float32 + 21, y: py.float32 + 21), 11, c.c2)
      drawCircle(Vector2(x: px.float32 + 21, y: py.float32 + 21), 5, c.c3)
    let kindLabel = case c.kind
      of mckPlayer: t(tkModsKindPlayer)
      of mckBullet: t(tkModsKindBullet)
      of mckDesktop: t(tkModsKindDesktop)
    let textX = px + 54
    let textW = int32(g.w) - 54 - 150
    drawText(fitWithEllipsis(c.name, textW, 15), textX, ry + 8, 15, ColText)
    drawText(fitWithEllipsis(kindLabel & "   " & c.key, textW, 11), textX, ry + 27, 11, ColAccent)
    if c.description.len > 0:
      drawText(fitWithEllipsis(c.description, textW, 11), textX, ry + 41, 11, ColMuted)
    drawButton(Rectangle(x: float32(g.x + g.w - 124), y: float32(ry + 14), width: 110, height: 30),
               (if equipped: t(tkModsUnequip) else: t(tkModsEquip)), true, not equipped)
  endScissorMode()

proc drawApps(mw: ModsWindow, g: Geo) =
  drawRectangle(g.logArea, ColPanel)
  drawRectangleLines(g.logArea, 1.0, Color(r: 50, g: 60, b: 70, a: 255))
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

proc drawLog(mw: ModsWindow, g: Geo) =
  drawRectangle(g.logArea, ColPanel)
  drawRectangleLines(g.logArea, 1.0, Color(r: 50, g: 60, b: 70, a: 255))
  if modLog.len == 0:
    drawText(t(tkModsLogEmpty), int32(g.x) + 12, int32(g.bodyY) + 12, 13, ColMuted)
    return
  beginVirtualScissorMode(int32(g.logArea.x), int32(g.logArea.y), int32(g.logArea.width), int32(g.logArea.height))
  let maxW = int32(g.logArea.width) - 20
  for i, line in modLog:
    let y = int32(g.logArea.y) + 6 + int32(i * LogLineH - mw.logScroll)
    if y + LogLineH < int32(g.logArea.y) or y > int32(g.logArea.y + g.logArea.height): continue
    let prefix = if line.modId.len > 0: "[" & line.modId & "] " else: ""
    let col = case line.level
      of mlInfo: ColText
      of mlWarn: ColWarn
      of mlError: ColErr
    drawText(fitWithEllipsis(prefix & line.text, maxW, 11), int32(g.logArea.x) + 10, y, 11, col)
  endScissorMode()

proc drawModsWindow*(mw: ModsWindow) =
  if not mw.window.visible: return
  drawWindowChrome(mw.window)
  if mw.window.minimized: return
  let g = mw.geometry()

  # tabs
  let labels: array[ModsTab, string] = [t(tkModsTabInstalled), t(tkModsTabModes),
                                        t(tkModsTabCosmetics), t(tkModsTabApps), t(tkModsTabLog)]
  for tab in ModsTab:
    let r = g.tabs[tab]
    let active = mw.tab == tab
    drawRectangle(r, if active: Color(r: 30, g: 70, b: 55, a: 255) else: Color(r: 28, g: 32, b: 42, a: 255))
    drawRectangleLines(r, 1.0, if active: ColAccent else: Color(r: 70, g: 78, b: 92, a: 255))
    let tw = measureText(labels[tab], 14)
    drawText(labels[tab], int32(r.x + (r.width - tw.float32) / 2), int32(r.y) + 7, 14,
             if active: ColText else: ColMuted)

  # the rule players must know
  let banner = Rectangle(x: g.x.float32, y: float32(g.y + TabH + 8), width: g.w.float32, height: BannerH.float32)
  let keeps = modsActive and not modsDisableAchievements   # every loaded mod keeps rewards
  let bannerText = t(if keeps: tkModsKeepsBanner else: tkModsCheatBanner)
  drawRectangle(banner, if keeps: Color(r: 12, g: 42, b: 30, a: 255) else: Color(r: 48, g: 34, b: 8, a: 255))
  drawRectangleLines(banner, 1.0, if keeps: Color(r: 60, g: 200, b: 140, a: 200)
                                  else: Color(r: 255, g: 176, b: 32, a: 200))
  let bannerSize = bestFitFontSize(bannerText, int32(g.w) - 16, 12, 10)
  drawText(fitWithEllipsis(bannerText, int32(g.w) - 16, bannerSize),
           int32(g.x) + 8, int32(banner.y) + (BannerH - bannerSize) div 2, bannerSize,
           if keeps: ColOk else: ColWarn)

  case mw.tab
  of mtInstalled: mw.drawInstalled(g)
  of mtModes: mw.drawModes(g)
  of mtCosmetics: mw.drawCosmetics(g)
  of mtApps: mw.drawApps(g)
  of mtLog: mw.drawLog(g)

  if mw.removeTarget.len > 0:
    mw.drawRemoveConfirm(g)
