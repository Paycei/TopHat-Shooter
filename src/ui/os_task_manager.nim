## OS-Style Task Manager (Pause Menu)
## Pause menu styled as system task manager with mouse support

import raylib, math, strutils
import ../types, ../powerup_data, ../localization, ../render_context, ../survival, ../patches, ../utils
import ui_helpers, icon_drawing

const
  TASK_MANAGER_WIDTH = 700
  TASK_MANAGER_HEIGHT = 500

const
  TaskManagerPanelW* = TASK_MANAGER_WIDTH
  TaskManagerPanelH* = TASK_MANAGER_HEIGHT
    ## Panel size, exported so callers can cap the UI scale against it.
  TITLE_BAR_HEIGHT = 35
  TAB_HEIGHT = 35
  BUTTON_HEIGHT = 40
  BUTTON_SPACING = 15

proc isMouseOverRect*(mousePos: Vector2, x, y, width, height: int32): bool =
  ## Helper to check if mouse is over a rectangle
  result = mousePos.x >= x.float32 and mousePos.x <= (x + width).float32 and
           mousePos.y >= y.float32 and mousePos.y <= (y + height).float32

proc drawTaskManagerTab(x, y, width: int32, text: string, active: bool, hovered: bool) =
  ## Draw a single tab button
  let bgColor = if active:
    Color(r: 45, g: 55, b: 70, a: 255)
  elif hovered:
    Color(r: 35, g: 45, b: 60, a: 255)
  else:
    Color(r: 25, g: 35, b: 50, a: 255)

  drawRectangle(x, y, width, TAB_HEIGHT, bgColor)

  # Tab border
  let borderColor = if active:
    Color(r: 0, g: 200, b: 255, a: 255)
  else:
    Color(r: 60, g: 70, b: 85, a: 255)

  drawRectangleLines(Rectangle(x: x.float32, y: y.float32,
                                width: width.float32, height: TAB_HEIGHT.float32),
                    if active: 2 else: 1, borderColor)

  # Tab text
  let textWidth = measureText(text, 14)
  let textColor = if active:
    Color(r: 0, g: 200, b: 255, a: 255)
  else:
    Color(r: 150, g: 150, b: 150, a: 255)

  drawText(text, x + (width - textWidth) div 2, y + 10, 14, textColor)

proc taskManagerTabs*(game: Game): seq[TaskManagerTab] =
  ## The tabs this run shows, left to right. Patches only exist in a roguelite
  ## run, so only that mode gets their tab.
  if game.mode == gmRoguelite and not game.rogueliteRun.isNil:
    @[tmtProcesses, tmtPatches, tmtPerformance]
  else:
    @[tmtProcesses, tmtPerformance]

proc stepTaskManagerTab*(game: Game, current: TaskManagerTab, step: int): TaskManagerTab =
  ## The tab `step` places from `current`, wrapping (Left/Right in the menu).
  let tabs = taskManagerTabs(game)
  let at = max(0, tabs.find(current))
  tabs[(at + step + tabs.len * 2) mod tabs.len]

proc taskManagerTabLabel(tab: TaskManagerTab): string =
  case tab
  of tmtProcesses: t("os_tab_processes")
  of tmtPatches: t("os_tab_patches")
  of tmtPerformance: t("os_tab_performance")
  of tmtSettings: ""

# ---------------------------------------------------------------------------
# Inspector tabs (Processes, Patches): the entries in a list on the left, the
# selected one explained in full on the right. Navigation (UP/DOWN, W/S, the
# D-pad, hover and the wheel), the row and pane frames and the text blocks are
# shared; each tab only says what goes in its rows and its pane.

const
  InspectorTitleH = 30'i32      ## the tab's own heading line
  InspectorRowH = 18'i32
  InspectorListW = 300'i32
  InspectorHintH = 18'i32       ## the hint line under the pane
  InspectorIcon = 44'i32        ## the pane's big glyph
  InspectorAccent = Color(r: 0, g: 200, b: 255, a: 255)
  InspectorDim = Color(r: 120, g: 135, b: 150, a: 255)

type
  InspectorNav = object
    selection: int              ## entry the pane shows
    scroll: int                 ## first entry in view

  InspectorLayout = object
    listX, listY, rows: int32   ## `rows` = how many entries fit in view
    paneX, paneY, paneW, paneH: int32

var
  processNav, patchNav: InspectorNav
  inspectorLastMouse = Vector2(x: -1, y: -1)
    ## Hover only moves the selection when the pointer actually moves: the
    ## pause menu reports the mouse as live every frame, so a cursor resting
    ## over the list would otherwise undo every UP/DOWN press.

proc inspectorLayout(x, y, width, height: int32): InspectorLayout =
  let top = y + 10 + InspectorTitleH
  result.listX = x + 10
  result.listY = top
  result.rows = max(1'i32, (y + height - top) div InspectorRowH)
  result.paneX = result.listX + InspectorListW + 10
  result.paneY = top
  result.paneW = x + width - 10 - result.paneX
  result.paneH = y + height - top - InspectorHintH

proc drawInspectorTitle(text: string, x, y: int32) =
  drawText(text, x + 10, y + 10, 16, InspectorAccent)

proc navigateInspector(nav: var InspectorNav, count: int, lay: InspectorLayout,
                       mouseSupported: bool) =
  ## One frame of list input: keys move the selection and scroll it into view,
  ## the wheel scrolls (dragging the selection along), hover picks a row.
  let visible = lay.rows.int
  var keyMoved = false
  if isKeyPressed(KeyboardKey.Up) or isKeyPressed(KeyboardKey.W) or gamepadNavPressed(gnUp):
    dec nav.selection
    keyMoved = true
  if isKeyPressed(KeyboardKey.Down) or isKeyPressed(KeyboardKey.S) or gamepadNavPressed(gnDown):
    inc nav.selection
    keyMoved = true
  nav.selection = clamp(nav.selection, 0, max(0, count - 1))
  let wheel = getPointerWheelMove()
  if wheel > 0.0'f32: dec nav.scroll
  elif wheel < 0.0'f32: inc nav.scroll
  if keyMoved:
    if nav.selection < nav.scroll: nav.scroll = nav.selection
    elif nav.selection >= nav.scroll + visible: nav.scroll = nav.selection - visible + 1
  nav.scroll = clamp(nav.scroll, 0, max(0, count - visible))
  if wheel != 0.0'f32:
    nav.selection = clamp(nav.selection, nav.scroll, min(count, nav.scroll + visible) - 1)

  let mouse = getVirtualMousePosition()
  let moved = mouse.x != inspectorLastMouse.x or mouse.y != inspectorLastMouse.y
  inspectorLastMouse = mouse
  if mouseSupported and (moved or isPointerPressed()):
    for i in 0..<min(visible, count - nav.scroll):
      if isMouseOverRect(mouse, lay.listX, lay.listY + i.int32 * InspectorRowH,
                         InspectorListW, InspectorRowH):
        nav.selection = nav.scroll + i

proc drawInspectorRowFrame(lay: InspectorLayout, slot: int, selected: bool): int32 =
  ## Background of the `slot`-th visible row; returns its y.
  result = lay.listY + slot.int32 * InspectorRowH
  if selected:
    drawRectangle(lay.listX, result, InspectorListW, InspectorRowH, withAlpha(InspectorAccent, 45))
    drawRectangleLines(Rectangle(x: lay.listX.float32, y: result.float32,
                                 width: InspectorListW.float32, height: InspectorRowH.float32),
                       1, withAlpha(InspectorAccent, 170))
  elif slot mod 2 == 0:
    drawRectangle(lay.listX, result, InspectorListW, InspectorRowH, Color(r: 30, g: 35, b: 45, a: 100))

proc drawInspectorRowText(lay: InspectorLayout, ry: int32, tag, name: string, nameColor: Color,
                          status: string, statusColor: Color, tagW: int32) =
  ## A row's text after its 16px glyph: a dim tag column (KB number, version),
  ## the name, and the status right-aligned.
  drawText(tag, lay.listX + 26, ry + 3, 12, InspectorDim)
  let statusW = measureText(status, 12)
  drawText(status, lay.listX + InspectorListW - 6 - statusW, ry + 3, 12, statusColor)
  let nameX = lay.listX + 26 + tagW + 8
  drawText(fitWithEllipsis(name, lay.listX + InspectorListW - 6 - statusW - 8 - nameX, 12),
           nameX, ry + 3, 12, nameColor)

proc drawInspectorScrollbar(lay: InspectorLayout, count: int, nav: InspectorNav) =
  if count <= lay.rows.int:
    return
  let trackX = lay.listX + InspectorListW + 3
  let trackH = lay.rows * InspectorRowH
  drawRectangle(trackX, lay.listY, 3, trackH, Color(r: 40, g: 48, b: 60, a: 255))
  let thumbH = max(12'i32, trackH * lay.rows div count.int32)
  let thumbY = lay.listY + (trackH - thumbH) * nav.scroll.int32 div max(1, count - lay.rows.int).int32
  drawRectangle(trackX, thumbY, 3, thumbH, withAlpha(InspectorAccent, 200))

proc drawInspectorPane(lay: InspectorLayout, accent: Color): tuple[iconX, iconY, textX, textW: int32] =
  ## The pane's frame and the backdrop of its big glyph. Returns where the
  ## glyph goes and the column the name / subtitle lines to its right use.
  let (x, y, w, h) = (lay.paneX, lay.paneY, lay.paneW, lay.paneH)
  drawRectangle(x, y, w, h, Color(r: 28, g: 34, b: 46, a: 255))
  drawRectangle(x, y, 3, h, accent)
  drawRectangleLines(Rectangle(x: x.float32, y: y.float32, width: w.float32, height: h.float32),
                     1, withAlpha(accent, 110))
  result.iconX = x + 16
  result.iconY = y + 16
  drawRectangle(result.iconX - 4, result.iconY - 4, InspectorIcon + 8, InspectorIcon + 8,
                withAlpha(accent, 30))
  result.textX = result.iconX + InspectorIcon + 14
  result.textW = x + w - 14 - result.textX

proc drawInspectorBody(lay: InspectorLayout, blocks: openArray[tuple[caption, text: string, color: Color]],
                       statusLabel: string, statusColor: Color) =
  ## Below the glyph: a divider, then each text block (an optional small
  ## caption over wrapped text), then the status line pinned to the bottom.
  ## Falls back from 14px to 12px when the blocks would run into the status.
  let x = lay.paneX + 14
  let w = lay.paneW - 28
  let top = lay.paneY + 16 + InspectorIcon + 18
  let bottom = lay.paneY + lay.paneH - 30
  drawLine(Vector2(x: x.float32, y: (top - 8).float32),
           Vector2(x: (x + w).float32, y: (top - 8).float32), 1, Color(r: 60, g: 70, b: 85, a: 255))

  var needed = 0'i32
  for b in blocks:
    if b.caption.len > 0: needed += 16
    needed += wrapTextLines(b.text, w, 14).len.int32 * 20 + 6
  let size = if needed <= bottom - top: 14'i32 else: 12'i32

  var ly = top
  for b in blocks:
    if b.caption.len > 0:
      drawText(b.caption, x, ly, 10, InspectorDim)
      ly += 16
    for line in wrapTextLines(b.text, w, size):
      if ly + size > bottom: break
      drawText(line, x, ly, size, b.color)
      ly += size + 6
    ly += 6

  let label = t("os_status") & ": "
  let sy = lay.paneY + lay.paneH - 26
  drawText(label, x, sy, 12, LightGray)
  drawText(statusLabel, x + measureText(label, 12), sy, 12, statusColor)

proc drawInspectorHint(lay: InspectorLayout, text: string) =
  drawText(text, lay.paneX, lay.paneY + lay.paneH + 5, 10, InspectorDim)

proc drawInspectorEmpty(text: string, x, y, width: int32) =
  var ly = y + 10 + InspectorTitleH
  for line in wrapTextLines(text, width - 40, 14):
    drawText(line, x + 20, ly, 14, Gray)
    ly += 20

# --- Patches -----------------------------------------------------------------

proc drawPatchesTab(game: Game, x, y, width, height: int32, mouseSupported: bool) =
  ## The run's patches in install order, and the selected one explained in
  ## full. The HUD only has room for names; this is where a player learns what
  ## each patch does.
  let relics = if game.rogueliteRun.isNil: @[] else: game.rogueliteRun.relics
  drawInspectorTitle(t("os_installed_patches") & " (" & $relics.len & "):", x, y)
  if relics.len == 0:
    drawInspectorEmpty(t("os_no_patches"), x, y, width)
    return

  let lay = inspectorLayout(x, y, width, height)
  navigateInspector(patchNav, relics.len, lay, mouseSupported)
  let tagW = measureText("KB-0000", 12)
  for slot in 0..<min(lay.rows.int, relics.len - patchNav.scroll):
    let i = patchNav.scroll + slot
    let patch = relics[i].relicType
    let status = patchStatus(game, patch)
    let spent = status in {psUsed, psStalled}
    let ry = drawInspectorRowFrame(lay, slot, i == patchNav.selection)
    let accent = patchAccent(patch)
    drawPatchIcon(lay.listX + 4, ry + 1, InspectorRowH - 2, patch,
                  if spent: withAlpha(accent, 100) else: accent)
    drawInspectorRowText(lay, ry, patchKbLabel(patch), patchName(patch),
                         if spent: Gray else: White,
                         patchStatusLabel(status), patchStatusColor(status), tagW)
  drawInspectorScrollbar(lay, relics.len, patchNav)

  # Pane: KB number and category under the name, then what it does.
  let patch = relics[patchNav.selection].relicType
  let accent = patchAccent(patch)
  let p = drawInspectorPane(lay, accent)
  drawPatchIcon(p.iconX, p.iconY, InspectorIcon, patch, accent)
  drawText(fitWithEllipsis(patchName(patch), p.textW, 18), p.textX, p.iconY + 2, 18, White)
  let kb = patchKbLabel(patch)
  drawText(kb, p.textX, p.iconY + 28, 12, Color(r: 140, g: 150, b: 165, a: 255))
  drawText(patchCategoryName(patchCategory(patch)).toUpperAscii,
           p.textX + measureText(kb, 12) + 12, p.iconY + 28, 12, accent)
  let status = patchStatus(game, patch)
  drawInspectorBody(lay, [(caption: "", text: patchDescription(patch),
                           color: Color(r: 215, g: 225, b: 235, a: 255))],
                    patchStatusLabel(status), patchStatusColor(status))
  drawInspectorHint(lay, t("os_patches_hint"))

# --- Processes (power-ups) -----------------------------------------------------

const
  LegendaryGold = Color(r: 255, g: 215, b: 0, a: 255)
  RunningGreen = Color(r: 100, g: 255, b: 100, a: 255)
  RechargeOrange = Color(r: 255, g: 165, b: 70, a: 255)

proc secondsText(s: float32): string =
  ## One decimal, rounded up so a spent ability never reads 0.0s.
  let tenths = max(1, int(ceil(s * 10.0'f32)))
  $(tenths div 10) & "." & $(tenths mod 10) & "s"

proc processStatus(game: Game, pu: PowerUp): tuple[short, full: string, color: Color] =
  ## RUNNING for a passive; for a [Q] ability, READY or how long until it is.
  let pt = pu.powerType
  if not allPowerUpDefs[pt].inLegendaryPanel:
    let s = t("os_status_running")
    return (s, s, RunningGreen)
  if abilityReady(game.player, pt):
    let s = t("patch_status_ready")
    return (s, s, patchStatusColor(psReady))
  let cd = abilityCooldown(game.player, pt)
  if cd > 0.0'f32:
    return (secondsText(cd), t("os_status_recharging").replace("$1", secondsText(cd)), RechargeOrange)
  # Off cooldown but blocked: Nova still running, Time Warp spent for the wave.
  let s = if pt == puNova and game.player.novaActive: t("patch_status_active")
          else: t("patch_status_used")
  (s, s, patchStatusColor(psUsed))

proc processColor(pu: PowerUp): Color =
  if pu.rarity == prLegendary: LegendaryGold else: getPowerUpColor(pu.powerType)

proc drawProcessesTab(game: Game, x, y, width, height: int32, mouseSupported: bool) =
  ## Installed power-ups in install order, and the selected one explained in
  ## full: its level, what it does now, and what its next level adds.
  let pus = game.player.powerUps
  drawInspectorTitle(t("os_running_processes") & " (" & $pus.len & "):", x, y)
  if pus.len == 0:
    drawInspectorEmpty(t("os_no_active_processes"), x, y, width)
    return

  let lay = inspectorLayout(x, y, width, height)
  navigateInspector(processNav, pus.len, lay, mouseSupported)
  let tagW = measureText("v0.0", 12)
  for slot in 0..<min(lay.rows.int, pus.len - processNav.scroll):
    let i = processNav.scroll + slot
    let pu = pus[i]
    let ry = drawInspectorRowFrame(lay, slot, i == processNav.selection)
    drawPowerUpIcon(lay.listX + 4, ry + 1, InspectorRowH - 2, pu.powerType, processColor(pu))
    let status = processStatus(game, pu)
    drawInspectorRowText(lay, ry, "v" & $pu.level & ".0", getPowerUpName(pu.powerType),
                         if pu.rarity == prLegendary: Color(r: 255, g: 232, b: 145, a: 255) else: White,
                         status.short, status.color, tagW)
  drawInspectorScrollbar(lay, pus.len, processNav)

  # Pane: level (or LEGENDARY) and ACTIVE ABILITY under the name, then what it
  # does at this level and, below max, what the next level brings.
  let pu = pus[processNav.selection]
  let pt = pu.powerType
  let color = processColor(pu)
  let p = drawInspectorPane(lay, color)
  drawPowerUpIcon(p.iconX, p.iconY, InspectorIcon, pt, color)
  drawText(fitWithEllipsis(getPowerUpName(pt), p.textW, 18), p.textX, p.iconY + 2, 18,
           if pu.rarity == prLegendary: Color(r: 255, g: 232, b: 145, a: 255) else: White)
  let maxLevel = max(pu.level, getPowerUpMaxLevel(pt))
  let rank = if pu.rarity == prLegendary: t("os_legendary")
             else: t("os_level_of").replace("$1", $pu.level).replace("$2", $maxLevel)
  drawText(rank, p.textX, p.iconY + 28, 12, color)
  if allPowerUpDefs[pt].inLegendaryPanel:
    drawText(t("os_active_ability"), p.textX + measureText(rank, 12) + 12, p.iconY + 28, 12,
             Color(r: 140, g: 150, b: 165, a: 255))

  let damage = game.player.damage
  var blocks = @[(caption: "", text: getPowerUpDescription(pt, pu.level, damage),
                  color: Color(r: 215, g: 225, b: 235, a: 255))]
  if pu.level < maxLevel:
    blocks.add (caption: t("os_next_level"), text: getPowerUpDescription(pt, pu.level + 1, damage),
                color: Color(r: 150, g: 165, b: 180, a: 255))
  let status = processStatus(game, pu)
  drawInspectorBody(lay, blocks, status.full, status.color)
  drawInspectorHint(lay, t("os_processes_hint"))

proc drawPerformanceTab(game: Game, x, y, width, height: int32, time: float32) =
  ## Draw the Performance tab showing game statistics
  var yOffset = y + 10

  drawText(t("os_system_performance") & ":", x + 10, yOffset, 16,
          Color(r: 0, g: 200, b: 255, a: 255))
  yOffset += 30

  # Current session stats
  let stats = [
    if game.mode == gmTimeSurvival: ("Phase", survivalPhaseReachedLabel(game))
    else: ("Wave", $game.currentWave),
    ("Uptime", $(game.time.int div 60) & ":" &
               (if game.time.int mod 60 < 10: "0" else: "") & $(game.time.int mod 60)),
    ("Threats Eliminated", $game.player.kills),
    ("Resources Collected", $game.player.coins),
    ("System Integrity", $round(game.player.hp).int & "/" & $round(game.player.maxHp).int),
    ("Active Processes", $game.player.powerUps.len),
    ("Defensive Barriers", $game.player.walls)
  ]

  for stat in stats:
    let (label, value) = stat
    drawText(label & ":", x + 30, yOffset, 14, LightGray)
    drawText(value, x + 300, yOffset, 14, White)
    yOffset += 25

proc drawQuitConfirmDialog*(game: Game): tuple[confirmed, cancelled: bool] =
  ## Draw an OS-style "Are you sure?" confirmation dialog over the task manager.
  result.confirmed = false
  result.cancelled  = false

  let sw = getVirtualScreenWidth()
  let sh = getVirtualScreenHeight()
  let mousePos = getVirtualMousePosition()

  const
    DW: int32 = 440
    DH: int32 = 200
    BTN_W: int32 = 160
    BTN_H: int32 = 40

  let dx: int32 = (sw - DW) div 2
  let dy: int32 = (sh - DH) div 2

  # Extra dark backdrop on top of the existing overlay
  drawRectangle(0'i32, 0'i32, sw, sh, Color(r: 0, g: 0, b: 0, a: 120))

  # Dialog shadow
  drawRectangle(dx + 6, dy + 6, DW, DH, Color(r: 0, g: 0, b: 0, a: 140))
  # Dialog background
  drawRectangle(dx, dy, DW, DH, Color(r: 20, g: 25, b: 35, a: 255))
  drawRectangleLines(Rectangle(x: dx.float32, y: dy.float32,
                               width: DW.float32, height: DH.float32),
                     3, Color(r: 255, g: 80, b: 80, a: 255))

  # Title bar
  let tbH: int32 = 35
  drawRectangle(dx, dy, DW, tbH, Color(r: 120, g: 30, b: 30, a: 255))
  let titleStr = "CONFIRM EXIT"
  let titleW = measureText(titleStr, 16)
  drawText(titleStr, dx + (DW - titleW) div 2, dy + 8, 16,
           Color(r: 255, g: 200, b: 200, a: 255))

  # Body text
  let bodyStr = "Return to main menu?"
  let bodyW = measureText(bodyStr, 18)
  drawText(bodyStr, dx + (DW - bodyW) div 2, dy + tbH + 28, 18, White)

  let subStr = "Your progress will be saved."
  let subW = measureText(subStr, 13)
  drawText(subStr, dx + (DW - subW) div 2, dy + tbH + 58, 13,
           Color(r: 200, g: 150, b: 150, a: 255))

  # Buttons row
  let btnY: int32  = dy + DH - BTN_H - 22
  let noX: int32   = dx + (DW div 2) - BTN_W - 12
  let yesX: int32  = dx + (DW div 2) + 12

  let noHov  = isMouseOverRect(mousePos, noX,  btnY, BTN_W, BTN_H)
  let yesHov = isMouseOverRect(mousePos, yesX, btnY, BTN_W, BTN_H)
  # Mouse confirm is gated by pauseMenuExitCooldown (2 s anti-accident window).
  # Keyboard confirm is gated by pauseMenuExitCooldown too, PLUS the tiny
  # frame-guard that prevents Q-open and Q-confirm firing in the same poll cycle.
  let mouseReady = game.pauseMenuExitCooldown <= 0.0
  let keyReady   = game.pauseMenuExitCooldown <= 0.0 and game.confirmQuitFrameGuard <= 0.0

  # Cancel button (green: safe)
  let noBg = if noHov: Color(r: 0, g: 150, b: 0, a: 255) else: Color(r: 0, g: 110, b: 0, a: 255)
  drawRectangle(noX, btnY, BTN_W, BTN_H, noBg)
  drawRectangleLines(Rectangle(x: noX.float32, y: btnY.float32,
                               width: BTN_W.float32, height: BTN_H.float32),
                     if noHov: 3 else: 2,
                     if noHov: Color(r: 0, g: 255, b: 100, a: 255) else: Color(r: 0, g: 200, b: 60, a: 255))
  let noText = "[ESC] CANCEL"
  let noTW = measureText(noText, 14)
  drawText(noText, noX + (BTN_W - noTW) div 2, btnY + 12, 14, White)

  # Confirm button (red: destructive) greyed while mouse cooldown is active
  let yesBg = if not mouseReady:
    Color(r: 90, g: 90, b: 90, a: 255)
  elif yesHov:
    Color(r: 160, g: 40, b: 40, a: 255)
  else:
    Color(r: 120, g: 30, b: 30, a: 255)

  drawRectangle(yesX, btnY, BTN_W, BTN_H, yesBg)
  drawRectangleLines(Rectangle(x: yesX.float32, y: btnY.float32,
                               width: BTN_W.float32, height: BTN_H.float32),
                     if (yesHov and mouseReady): 3 else: 2,
                     if not mouseReady: Color(r: 140, g: 140, b: 140, a: 255)
                     elif yesHov: Color(r: 255, g: 100, b: 100, a: 255) else: Color(r: 200, g: 60, b: 60, a: 255))

  # Replace quit text with remaining seconds while mouse-cooldown is active
  let yesText = if mouseReady:
    "[Q] EXIT"
  else:
    $(int(ceil(game.pauseMenuExitCooldown)))
  let yesTW = measureText(yesText, 14)
  drawText(yesText, yesX + (BTN_W - yesTW) div 2, btnY + 12, 14, White)

  # Input keyboard uses keyReady (frame-guard only); mouse uses mouseReady (2 s cooldown).
  if isPointerPressed():
    if noHov:
      result.cancelled = true
    elif yesHov and mouseReady:
      result.confirmed = true
  if isKeyPressed(Escape): result.cancelled = true
  if isKeyPressed(Q)     and keyReady: result.confirmed = true
  if isKeyPressed(Enter) and keyReady: result.confirmed = true

proc drawOSTaskManager*(game: Game, selectedTab: TaskManagerTab): tuple[resumeClicked, settingsClicked, exitClicked: bool, newTab: TaskManagerTab] =
  ## Draw the task manager (pause menu)
  ## Returns tuple indicating which button was clicked (if any) and which tab should be selected
  result.resumeClicked = false
  result.settingsClicked = false
  result.exitClicked = false
  result.newTab = selectedTab

  let screenWidth = getVirtualScreenWidth()
  let screenHeight = getVirtualScreenHeight()
  let mousePos = getVirtualMousePosition()
  let mouseSupported = game.mouseMovedRecently

  # Dark overlay
  drawRectangle(0, 0, screenWidth, screenHeight, Color(r: 0, g: 0, b: 0, a: 200))

  # Calculate window position (centered)
  let windowX = (screenWidth - TASK_MANAGER_WIDTH) div 2
  let windowY = (screenHeight - TASK_MANAGER_HEIGHT) div 2

  # Window shadow
  drawRectangle((windowX + 5).int32, (windowY + 5).int32,
               TASK_MANAGER_WIDTH, TASK_MANAGER_HEIGHT,
               Color(r: 0, g: 0, b: 0, a: 120))

  # Window background
  drawRectangle(windowX, windowY, TASK_MANAGER_WIDTH, TASK_MANAGER_HEIGHT,
               Color(r: 20, g: 25, b: 35, a: 255))

  # Window border
  drawRectangleLines(Rectangle(x: windowX.float32, y: windowY.float32,
                                width: TASK_MANAGER_WIDTH.float32, height: TASK_MANAGER_HEIGHT.float32),
                    3, Color(r: 0, g: 200, b: 255, a: 255))

  # Title bar
  drawRectangle(windowX, windowY, TASK_MANAGER_WIDTH, TITLE_BAR_HEIGHT,
               Color(r: 35, g: 45, b: 60, a: 255))

  drawText(t("os_system_manager"), windowX + 15, windowY + 8, 18,
          Color(r: 0, g: 200, b: 255, a: 255))

  # Tabs: Processes and Performance, plus Patches in a roguelite run.
  let tabY = windowY + TITLE_BAR_HEIGHT
  let tabs = taskManagerTabs(game)
  # A tab this run doesn't have (a stale selection) falls back to Processes.
  let shownTab = if selectedTab in tabs: selectedTab else: tmtProcesses
  let tabWidth = (TASK_MANAGER_WIDTH div tabs.len).int32
  for i, tab in tabs:
    let tx = windowX + i.int32 * tabWidth
    # The last tab absorbs the rounding so the bar spans the whole window.
    let tw = if i == tabs.high: windowX + TASK_MANAGER_WIDTH - tx else: tabWidth
    let hovered = mouseSupported and isMouseOverRect(mousePos, tx, tabY, tw, TAB_HEIGHT)
    if hovered and isPointerPressed():
      result.newTab = tab
    drawTaskManagerTab(tx, tabY, tw, taskManagerTabLabel(tab), shownTab == tab, hovered)

  # Content area
  let contentY = tabY + TAB_HEIGHT + 10
  let contentHeight = TASK_MANAGER_HEIGHT - TITLE_BAR_HEIGHT - TAB_HEIGHT - 165

  # Bottom buttons
  let buttonY = windowY + TASK_MANAGER_HEIGHT - 80
  let buttonsStartX = windowX + (TASK_MANAGER_WIDTH - 600) div 2

  # The inspector tabs run down to the buttons, or to the lives panel above
  # them in the modes that have one.
  let showsLives = game.mode in RestorePointModes
  let inspectorBottom = if showsLives: buttonY - LivesPanelHeight - 14 - 10
                        else: buttonY - 10
  case shownTab
  of tmtProcesses:
    drawProcessesTab(game, windowX, contentY, TASK_MANAGER_WIDTH.int32, inspectorBottom - contentY,
                     mouseSupported)
  of tmtPatches:
    drawPatchesTab(game, windowX, contentY, TASK_MANAGER_WIDTH.int32, inspectorBottom - contentY,
                   mouseSupported)
  of tmtPerformance:
    drawPerformanceTab(game, windowX, contentY, TASK_MANAGER_WIDTH.int32, contentHeight.int32, game.time)
  of tmtSettings:
    discard

  # Lives panel between the tab content and the buttons, in the modes with a
  # continue budget (RestorePointModes).
  if showsLives and restorePointsOffline(game):
    drawEndlessRestorePanel(windowX + 20, buttonY - LivesPanelHeight - 14,
                            TASK_MANAGER_WIDTH.int32 - 40, game.mode, game.time)
  elif showsLives:
    drawLivesPanel(windowX + 20, buttonY - LivesPanelHeight - 14,
                   TASK_MANAGER_WIDTH.int32 - 40, game.livesUsed,
                   difficultyMaxLives(game.mode), UnlimitedLives, game.time)

  # Check mouse hover for buttons
  let exitHovered = mouseSupported and isMouseOverRect(mousePos, buttonsStartX, buttonY, 180, BUTTON_HEIGHT)
  let settingsX = buttonsStartX + 180 + BUTTON_SPACING
  let settingsHovered = mouseSupported and isMouseOverRect(mousePos, settingsX, buttonY, 180, BUTTON_HEIGHT)
  let resumeX = settingsX + 180 + BUTTON_SPACING
  let resumeHovered = mouseSupported and isMouseOverRect(mousePos, resumeX, buttonY, 180, BUTTON_HEIGHT)

  # Handle button clicks
  if mouseSupported and isPointerPressed():
    if exitHovered:
      result.exitClicked = true
    elif settingsHovered:
      result.settingsClicked = true
    elif resumeHovered:
      result.resumeClicked = true

  # Exit button
  let exitBgColor = if exitHovered:
    Color(r: 150, g: 40, b: 40, a: 255)
  else:
    Color(r: 120, g: 30, b: 30, a: 255)

  drawRectangle(buttonsStartX, buttonY, 180, BUTTON_HEIGHT, exitBgColor)
  drawRectangleLines(Rectangle(x: buttonsStartX.float32, y: buttonY.float32,
                                width: 180.0, height: BUTTON_HEIGHT.float32),
                    if exitHovered: 3 else: 2,
                    if exitHovered: Color(r: 255, g: 100, b: 100, a: 255) else: Color(r: 255, g: 80, b: 80, a: 255))
  let exitText = "[Q] EXIT"
  let exitWidth = measureText(exitText, 14)
  drawText(exitText, buttonsStartX + (180 - exitWidth) div 2,
          buttonY + 12, 14, White)

  # Settings button
  let settingsBgColor = if settingsHovered:
    Color(r: 80, g: 90, b: 105, a: 255)
  else:
    Color(r: 60, g: 70, b: 85, a: 255)

  drawRectangle(settingsX, buttonY, 180, BUTTON_HEIGHT, settingsBgColor)
  drawRectangleLines(Rectangle(x: settingsX.float32, y: buttonY.float32,
                                width: 180.0, height: BUTTON_HEIGHT.float32),
                    if settingsHovered: 3 else: 2,
                    if settingsHovered: Color(r: 150, g: 170, b: 190, a: 255) else: Color(r: 120, g: 140, b: 160, a: 255))
  let settingsText = "[TAB] SETTINGS"
  let settingsWidth = measureText(settingsText, 14)
  drawText(settingsText, settingsX + (180 - settingsWidth) div 2,
          buttonY + 12, 14, White)

  # Resume button
  let resumeBgColor = if resumeHovered:
    Color(r: 0, g: 150, b: 0, a: 255)
  else:
    Color(r: 0, g: 120, b: 0, a: 255)

  drawRectangle(resumeX, buttonY, 180, BUTTON_HEIGHT, resumeBgColor)
  drawRectangleLines(Rectangle(x: resumeX.float32, y: buttonY.float32,
                                width: 180.0, height: BUTTON_HEIGHT.float32),
                    if resumeHovered: 3 else: 2,
                    if resumeHovered: Color(r: 0, g: 255, b: 100, a: 255) else: Color(r: 0, g: 255, b: 0, a: 255))
  let resumeText = "[SPACE] RESUME"
  let resumeWidth = measureText(resumeText, 14)
  drawText(resumeText, resumeX + (180 - resumeWidth) div 2,
          buttonY + 12, 14, White)

  # Status message
  drawText(t("os_system_paused") & " - " & t("os_press_space_continue"),
          windowX + 20, windowY + TASK_MANAGER_HEIGHT - 30, 12, LightGray)
