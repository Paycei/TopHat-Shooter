## The script-facing in-run UI (MODDING.md "In-run UI"): the `ui` library
## (screens over a run, immediate-mode widgets, toasts and banners, and the
## game-shipped dialogue / choose / cutscene screens), register.hudCard and
## register.pauseAction.
##
## HIGH layer: the loader installs it after mod_content_api. The open screens,
## HUD cards and pause actions live in mod_registry (game.nim and the pause
## menu read them); nothing here is ever saved.
##
## Widgets read the pointer from mod_hooks.uiPointer, which whoever draws sets
## for its own coordinates (a screen or a HUD card: the HUD's layer; an app:
## its canvas), so the same ui.button works in all three, with the mouse or a
## pad (A presses like a click; the pad's menu cursor points).

import std/[strutils, math]
import raylib
import ../draw_prims
import ../types, ../utils
import ../ui/hud_dock
import lua_bridge, mod_state, mod_hooks, mod_reflect, mod_api, mod_registry

const
  OpenKeys = ["draw", "update", "click", "onClose", "pause", "closeOnBack", "layer"]
  HudCardKeys = ["id", "title", "color", "height", "measure", "draw", "classic"]
  PauseActionKeys = ["id", "name", "onClick"]
  WidgetColor = Color(r: 0, g: 200, b: 255, a: 255)

  Prelude = staticRead("ui_prelude.lua")
    ## ui.dialogue, ui.choose and ui.cutscene, written in Lua on top of ui.open
    ## and the widgets: they run as the mod that calls them.

proc requireUiDrawing(vm: VM, fname: string) =
  if modCtx.drawing != dtHud:
    vm.runtimeError("ui." & fname & " draws: use it inside a screen's draw, a HUD card, " &
                    "an app or drawHud")

proc inside(x, y, w, h: float32): bool {.inline.} =
  uiPointer.x >= x and uiPointer.x < x + w and uiPointer.y >= y and uiPointer.y < y + h

proc rect4(vm: VM, args: openArray[ScriptValue], fname: string): tuple[x, y, w, h: float32] =
  (vm.checkNum(args, 0, fname).float32, vm.checkNum(args, 1, fname).float32,
   vm.checkNum(args, 2, fname).float32, vm.checkNum(args, 3, fname).float32)

proc optColor(vm: VM, opts: ScriptValue, key, what: string, def: Color): Color =
  if opts.kind != vkTable: return def
  let c = rawGetStr(opts.tbl, key)
  if c.kind == vkNil: def else: parseColor(vm, c, what)

proc fnOr(vm: VM, t: ScriptTable, key, what: string): ScriptValue =
  result = rawGetStr(t, key)
  if result.kind notin {vkNil, vkFunction, vkNative}:
    vm.runtimeError(what & "." & key & " must be a function")

proc modalHandle(id: int): ScriptValue =
  ## What ui.open returns: {id = n, close = fn, isOpen = fn}.
  let t = newScriptTable()
  rawSet(t, vstr("id"), vnum(id))
  t.reg("close") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    closeModModal(id)
  t.reg("isOpen") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ret.setRet(vbool(modModalOpen(id)))
  vtable(t)

proc handleId(vm: VM, v: ScriptValue, fname: string): int =
  case v.kind
  of vkNumber: int(v.n)
  of vkTable:
    let id = rawGetStr(v.tbl, "id")
    if id.kind != vkNumber: vm.runtimeError("ui." & fname & ": a screen (what ui.open returned) expected")
    int(id.n)
  else: vm.runtimeError("ui." & fname & ": a screen (what ui.open returned) expected")

proc installModUi*(base: ScriptTable) =
  let uiT = newScriptTable()

  # ---- screens
  uiT.reg("open") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## local s = ui.open{draw = fn(w, h), update = fn(dt), click = fn(x, y, button),
    ##   onClose = fn(), pause = true, closeOnBack = true, layer = "hud" | "screen"}
    ## -> {id, close = fn, isOpen = fn}. s:close() closes it.
    let owner = vm.requireOwner("ui.open")
    discard vm.requireRunGame()
    let t = vm.checkTable(args, 0, "ui.open")
    vm.checkKeys(t, OpenKeys, "ui.open")
    var m = ModModal(owner: owner, pause: true, closeOnBack: true, layer: mlHud)
    m.draw = vm.fnOr(t, "draw", "ui.open")
    if not m.draw.isFn: vm.runtimeError("ui.open needs draw = function(w, h)")
    m.update = vm.fnOr(t, "update", "ui.open")
    m.click = vm.fnOr(t, "click", "ui.open")
    m.onClose = vm.fnOr(t, "onClose", "ui.open")
    let p = rawGetStr(t, "pause")
    if p.kind != vkNil: m.pause = truthy(p)
    let b = rawGetStr(t, "closeOnBack")
    if b.kind != vkNil: m.closeOnBack = truthy(b)
    let l = rawGetStr(t, "layer")
    if l.kind == vkString:
      case l.str.s
      of "hud": m.layer = mlHud
      of "screen": m.layer = mlScreen
      else: vm.runtimeError("ui.open.layer must be \"hud\" or \"screen\"")
    elif l.kind != vkNil: vm.runtimeError("ui.open.layer must be \"hud\" or \"screen\"")
    if modModals.len >= 32: vm.runtimeError("ui.open: 32 screens are already open")
    ret.setRet(modalHandle(openModModal(m)))
  uiT.reg("close") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    closeModModal(vm.handleId(arg(args, 0), "close"))
  uiT.reg("isOpen") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ret.setRet(vbool(modModalOpen(vm.handleId(arg(args, 0), "isOpen"))))
  uiT.reg("closeAll") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## Closes every screen this mod opened.
    let owner = vm.requireOwner("ui.closeAll")
    var ids: seq[int]
    for m in modModals:
      if m.owner == owner: ids.add(m.id)
    for id in ids: closeModModal(id)

  # ---- widgets (immediate mode)
  uiT.reg("panel") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## ui.panel(x, y, w, h [, {title, color}]) -> the y below its title
    vm.requireUiDrawing("panel")
    let (x, y, w, h) = vm.rect4(args, "panel")
    let opts = arg(args, 4)
    let col = vm.optColor(opts, "color", "ui.panel.color", WidgetColor)
    drawDockCard(x.int32, y.int32, w.int32, h.int32, col)
    var below = y
    if opts.kind == vkTable:
      let tt = rawGetStr(opts.tbl, "title")
      if tt.kind == vkString:
        below = drawDockHeader(x.int32, y.int32, w.int32, tt.str.s, col).float32
    ret.setRet(vnum(below.float64 + 4))
  uiT.reg("button") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## ui.button(x, y, w, h, label [, {color, enabled = true}]) -> true the frame it is clicked
    vm.requireUiDrawing("button")
    let (x, y, w, h) = vm.rect4(args, "button")
    let label = vm.checkStr(args, 4, "button")
    let opts = arg(args, 5)
    let col = vm.optColor(opts, "color", "ui.button.color", WidgetColor)
    let enabled = opts.kind != vkTable or rawGetStr(opts.tbl, "enabled").kind == vkNil or
                  truthy(rawGetStr(opts.tbl, "enabled"))
    let hover = enabled and not uiPointer.consumed and inside(x, y, w, h)
    let bg = if not enabled: Color(r: 30, g: 34, b: 42, a: 230)
             elif hover and uiPointer.down: withAlpha(col, 120)
             elif hover: withAlpha(col, 70)
             else: Color(r: 14, g: 22, b: 34, a: 235)
    drawRectangle(Rectangle(x: x, y: y, width: w, height: h), bg)
    drawRectOutline(Rectangle(x: x, y: y, width: w, height: h), if hover: 2 else: 1,
                    if enabled: withAlpha(col, if hover: 255 else: 170) else: Color(r: 70, g: 76, b: 88, a: 255))
    let size = clamp(int32(h * 0.45), 10, 22)
    let tw = measureText(label, size)
    drawText(label, int32(x + (w - tw.float32) / 2), int32(y + (h - size.float32) / 2), size,
             if enabled: Color(r: 230, g: 240, b: 250, a: 255) else: Color(r: 110, g: 116, b: 128, a: 255))
    let clicked = hover and uiPointer.pressed
    if clicked: uiPointer.consumed = true
    ret.setRet(vbool(clicked))
  uiT.reg("label") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## ui.label(text, x, y [, {size = 14, color, align = "left" | "center" | "right",
    ##   width = px (wraps)}]) -> height drawn
    vm.requireUiDrawing("label")
    let text = vm.checkStr(args, 0, "label")
    var x = vm.checkNum(args, 1, "label").float32
    let y = vm.checkNum(args, 2, "label").float32
    let opts = arg(args, 3)
    var size = 14'i32
    var align = "left"
    var width = 0'f32
    if opts.kind == vkTable:
      vm.checkKeys(opts.tbl, ["size", "color", "align", "width"], "ui.label")
      let s = rawGetStr(opts.tbl, "size")
      if s.kind == vkNumber: size = clamp(int32(s.n), 8, 96)
      let a = rawGetStr(opts.tbl, "align")
      if a.kind == vkString: align = a.str.s
      let wv = rawGetStr(opts.tbl, "width")
      if wv.kind == vkNumber: width = max(0'f32, wv.n.float32)
    let col = vm.optColor(opts, "color", "ui.label.color", Color(r: 228, g: 240, b: 250, a: 255))
    var lines: seq[string]
    if width > 0:
      for para in text.split('\n'):
        var line = ""
        for word in para.splitWhitespace():
          let cand = if line.len == 0: word else: line & " " & word
          if line.len > 0 and measureText(cand, size).float32 > width:
            lines.add(line)
            line = word
          else:
            line = cand
        lines.add(line)
    else:
      lines = text.split('\n')
    var ly = y
    for line in lines:
      let lw = measureText(line, size).float32
      let lx = case align
        of "center": x + ((if width > 0: width else: 0) - lw) / 2 - (if width > 0: 0'f32 else: 0)
        of "right": x + (if width > 0: width else: 0) - lw
        else: x
      drawText(line, lx.int32, ly.int32, size, col)
      ly += size.float32 + 3
    ret.setRet(vnum((ly - y).float64))
  uiT.reg("progress") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## ui.progress(x, y, w, h, fraction [, color])
    vm.requireUiDrawing("progress")
    let (x, y, w, h) = vm.rect4(args, "progress")
    let frac = vm.checkNum(args, 4, "progress").float32
    let col = if arg(args, 5).kind == vkNil: WidgetColor else: parseColor(vm, arg(args, 5), "ui.progress")
    drawDockBar(x.int32, y.int32, w.int32, h.int32, frac, col)
  uiT.reg("checkbox") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## ui.checkbox(x, y, label, checked) -> checked (flipped the frame it is clicked)
    vm.requireUiDrawing("checkbox")
    let x = vm.checkNum(args, 0, "checkbox").float32
    let y = vm.checkNum(args, 1, "checkbox").float32
    let label = vm.checkStr(args, 2, "checkbox")
    var checked = truthy(arg(args, 3))
    let w = 22'f32 + measureText(label, 14).float32
    let hover = not uiPointer.consumed and inside(x, y, w, 16)
    drawRectangle(Rectangle(x: x, y: y, width: 16, height: 16), Color(r: 14, g: 22, b: 34, a: 235))
    drawRectOutline(Rectangle(x: x, y: y, width: 16, height: 16), 1,
                    withAlpha(WidgetColor, if hover: 255 else: 160))
    if hover and uiPointer.pressed:
      checked = not checked
      uiPointer.consumed = true
    if checked: drawRectangle(Rectangle(x: x + 4, y: y + 4, width: 8, height: 8), WidgetColor)
    drawText(label, int32(x + 22), int32(y + 1), 14, Color(r: 228, g: 240, b: 250, a: 255))
    ret.setRet(vbool(checked))
  uiT.reg("slider") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## ui.slider(x, y, w, value, min, max) -> value (dragged while held over it)
    vm.requireUiDrawing("slider")
    let x = vm.checkNum(args, 0, "slider").float32
    let y = vm.checkNum(args, 1, "slider").float32
    let w = max(10'f32, vm.checkNum(args, 2, "slider").float32)
    let lo = vm.checkNum(args, 4, "slider")
    let hi = vm.checkNum(args, 5, "slider")
    var v = clamp(vm.checkNum(args, 3, "slider"), min(lo, hi), max(lo, hi))
    let hover = not uiPointer.consumed and inside(x - 6, y - 8, w + 12, 18)
    if hover and uiPointer.down and hi != lo:
      v = lo + (hi - lo) * clamp((uiPointer.x - x) / w, 0'f32, 1'f32).float64
      if uiPointer.pressed: uiPointer.consumed = true
    let frac = if hi != lo: ((v - lo) / (hi - lo)).float32 else: 0'f32
    drawDockBar(x.int32, int32(y - 2), w.int32, 4, frac, WidgetColor)
    drawDisc(Vector2(x: x + w * frac, y: y), if hover: 7 else: 6, WidgetColor)
    ret.setRet(vnum(v))
  uiT.reg("pointer") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## ui.pointer() -> x, y, pressed, down: the pointer in what you are drawing
    ret.setRet([vnum(uiPointer.x.float64), vnum(uiPointer.y.float64),
                vbool(uiPointer.pressed and not uiPointer.consumed), vbool(uiPointer.down)])

  # ---- feedback
  uiT.reg("toast") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## ui.toast(text): a notification (over the run, or on the desktop)
    let text = vm.checkStr(args, 0, "toast")
    let g = modCtx.game
    if not g.isNil and not modCtx.inPvP: g.pendingToasts.add(text)
    else: modNotices.add(text)
  uiT.reg("banner") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## ui.banner(title [, subtitle, color, seconds = 2.5]): a big centred line over the run
    discard vm.requireRunGame()
    let secs = clamp(vm.optNum(args, 3, "banner", 2.5).float32, 0.2'f32, 30'f32)
    modBanner = (vm.checkStr(args, 0, "banner"), vm.optStr(args, 1, "banner", ""),
                 (if arg(args, 2).kind == vkNil: WidgetColor else: parseColor(vm, arg(args, 2), "ui.banner")),
                 secs, secs)
  rawSet(base, vstr("ui"), vtable(uiT))

  # ---- register.hudCard / register.pauseAction
  let registerT = rawGetStr(base, "register").tbl
  registerT.reg("hudCard") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## register.hudCard{id = "souls", title = "SOULS", color = "#a040ff",
    ##   height = 40 | measure = fn(w) -> height, draw = fn(x, y, w, h), classic = true}
    let owner = vm.requireLoading("register.hudCard")
    let t = vm.checkTable(args, 0, "register.hudCard")
    vm.checkKeys(t, HudCardKeys, "register.hudCard")
    let key = mods[owner].id & ":" & vm.checkName(t, "register.hudCard")
    for c in hudCardDefs:
      if c.key == key: vm.runtimeError("register.hudCard: '" & key & "' is already registered")
    var c = HudCardDef(key: key, owner: owner, color: WidgetColor, height: 40, classic: true)
    (c.titleEn, c.titleEs) = vm.textPair(rawGetStr(t, "title"), "register.hudCard.title")
    let col = rawGetStr(t, "color")
    if col.kind != vkNil: c.color = parseColor(vm, col, "register.hudCard.color")
    let h = rawGetStr(t, "height")
    if h.kind == vkNumber: c.height = clamp(int(h.n), 0, 600)
    elif h.kind != vkNil: vm.runtimeError("register.hudCard.height must be a number")
    c.measure = vm.fnOr(t, "measure", "register.hudCard")
    c.draw = vm.fnOr(t, "draw", "register.hudCard")
    if not c.draw.isFn: vm.runtimeError("register.hudCard needs draw = function(x, y, w, h)")
    let cl = rawGetStr(t, "classic")
    if cl.kind != vkNil: c.classic = truthy(cl)
    hudCardDefs.add(c)
    ret.setRet(vstr(key))
  registerT.reg("pauseAction") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## register.pauseAction{id = "skipIntro", name = "Skip the intro", onClick = fn(game)}
    ## -- a button in the pause menu's MODS tab
    let owner = vm.requireLoading("register.pauseAction")
    let t = vm.checkTable(args, 0, "register.pauseAction")
    vm.checkKeys(t, PauseActionKeys, "register.pauseAction")
    let key = mods[owner].id & ":" & vm.checkName(t, "register.pauseAction")
    for a in pauseActionDefs:
      if a.key == key: vm.runtimeError("register.pauseAction: '" & key & "' is already registered")
    var a = PauseActionDef(key: key, owner: owner)
    (a.nameEn, a.nameEs) = vm.textPair(rawGetStr(t, "name"), "register.pauseAction.name")
    if a.nameEn.len == 0: a.nameEn = key.split(':')[1]
    a.onClick = vm.fnOr(t, "onClick", "register.pauseAction")
    if not a.onClick.isFn: vm.runtimeError("register.pauseAction needs onClick = function(game)")
    pauseActionDefs.add(a)
    ret.setRet(vstr(key))

  # ---- the game-shipped screens, in Lua (ui.dialogue, ui.choose, ui.cutscene)
  try:
    let cl = modVM.loadChunk(Prelude, "=ui_prelude", base)
    var r: RetVals
    let err = protectedCall(modVM, vfunc(cl), [], r, LoadStepBudget)
    if err.len > 0: modLogAdd(mlError, "", "ui prelude: " & err)
  except ScriptError as e:
    modLogAdd(mlError, "", "ui prelude: " & e.msg)
