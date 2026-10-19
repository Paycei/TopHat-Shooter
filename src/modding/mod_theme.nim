## The script-facing interface themes (MODDING.md "Interface themes"):
## register.theme and the `theme` library.
##
## HIGH layer: the loader installs it after mod_engine. The themes themselves
## live in ui/ui_theme.nim (the registry the interface draws from), which
## drops a mod's themes on reload; the player's choice is the saved theme id
## (Settings.interfaceTheme), so a theme from a mod that is not loaded just
## falls back to the stock one until it is again.

import raylib
import ../settings, ../save_system
import ../ui/ui_theme
import lua_bridge, mod_hooks, mod_reflect, mod_api

const ThemeKeys = ["id", "name", "base", "surface", "raised", "text", "muted", "accent", "wallpaper"]

proc colorArg(vm: VM, args: openArray[ScriptValue], fname: string): Color =
  if args.len == 0: vm.runtimeError(fname & ": colour expected")
  parseColor(vm, args[0], fname)

proc resolveTheme(id: string): UiTheme =
  ## `id` as given, else as one of the calling mod's own ("midnight" for
  ## "<mod id>:midnight").
  result = findTheme(id)
  let m = currentMod()
  if result.isNil and not m.isNil:
    result = findTheme(m.id & ":" & id)

proc themeColors(th: UiTheme): ScriptValue =
  let t = newScriptTable()
  rawSet(t, vstr("id"), vstr(th.id))
  rawSet(t, vstr("name"), vstr(themeName(th)))
  rawSet(t, vstr("base"), vstr($th.shell))
  rawSet(t, vstr("light"), vbool(th.light))
  for (key, c) in [("surface", th.surface), ("raised", th.raised), ("text", th.text),
                   ("muted", th.muted), ("accent", th.accent)]:
    rawSet(t, vstr(key), colorValue(c))
  vtable(t)

proc installModTheme*(base: ScriptTable) =
  # ---- register.theme
  let registerT = rawGetStr(base, "register").tbl
  registerT.reg("theme") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## register.theme{id = "midnight", name = {en = "Midnight", es = "Medianoche"},
    ##   base = "tophat" | "ckn", surface = "#101626", raised = "#2a3350",
    ##   text = "#f0f4ff", muted = "#8a93a8", accent = "#ff4fd8",
    ##   wallpaper = "art/wall.png"} -> "<mod id>:midnight"
    ## Unset colours come from the base theme.
    let owner = vm.requireLoading("register.theme")
    let t = vm.checkTable(args, 0, "register.theme")
    vm.checkKeys(t, ThemeKeys, "register.theme")
    let key = mods[owner].id & ":" & vm.checkName(t, "register.theme")
    var shell = ssTopHat
    let bv = rawGetStr(t, "base")
    if bv.kind == vkString:
      case bv.str.s
      of "tophat": shell = ssTopHat
      of "ckn": shell = ssCkn
      else: vm.runtimeError("register.theme: base must be \"tophat\" or \"ckn\"")
    elif bv.kind != vkNil:
      vm.runtimeError("register.theme: base must be \"tophat\" or \"ckn\"")
    let b = findTheme($shell)
    let (nameEn, nameEs) = vm.textPair(rawGetStr(t, "name"), "name")
    let wv = rawGetStr(t, "wallpaper")
    let th = newTheme(key, shell,
                      vm.colorField(t, "surface", "register.theme", b.surface), vm.colorField(t, "raised", "register.theme", b.raised),
                      vm.colorField(t, "text", "register.theme", b.text), vm.colorField(t, "muted", "register.theme", b.muted),
                      vm.colorField(t, "accent", "register.theme", b.accent),
                      owner = owner, name = (if nameEn.len > 0: nameEn else: key), nameEs = nameEs,
                      wallpaper = (if wv.kind == vkNil: 0 else: vm.textureId(wv, "register.theme")))
    if not addTheme(th):
      vm.runtimeError("register.theme: '" & key & "' is already registered")
    ret.setRet(vstr(key))

  # ---- theme
  let themeT = newScriptTable()
  themeT.reg("current") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## theme.current() -> the id of the theme the interface is drawn in
    ret.setRet(vstr(chosenTheme().id))
  themeT.reg("list") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## theme.list() -> the ids of every theme the player can pick right now
    let t = newScriptTable()
    for th in unlockedThemes():
      t.add(vstr(th.id))
    ret.setRet(vtable(t))
  themeT.reg("set") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## theme.set(id) -> true: the player's theme is now `id` (saved, as if
    ## picked in Settings), even one the player has not unlocked. false: no
    ## such theme. Your own themes can be named without the "<mod id>:" prefix.
    let th = resolveTheme(vm.checkStr(args, 0, "theme.set"))
    let ok = not th.isNil and not globalSettings.isNil
    if ok: globalSettings.interfaceTheme = th.id
    if ok and not globalSettings.isNil:
      discard saveSettings(globalSettings)
    ret.setRet(vbool(ok))
  themeT.reg("colors") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## theme.colors([id]) -> {id, name, base, light, surface, raised, text,
    ## muted, accent} of the theme in use (or of `id`; nil if there is none)
    if args.len > 0 and args[0].kind != vkNil:
      let th = resolveTheme(vm.checkStr(args, 0, "theme.colors"))
      ret.setRet(if th.isNil: NilValue else: themeColors(th))
    else:
      ret.setRet(themeColors(chosenTheme()))
  # The roles the game's own interface draws with: pass the colour you would
  # use on the stock (dark) theme and get it back in the theme in use.
  themeT.reg("surface") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## theme.surface(color) -> a fill (panel, card, button) in the theme in use
    ret.setRet(colorValue(uiSurface(vm.colorArg(args, "theme.surface"))))
  themeT.reg("line") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## theme.line(color) -> a border or divider in the theme in use
    ret.setRet(colorValue(uiLine(vm.colorArg(args, "theme.line"))))
  themeT.reg("ink") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## theme.ink(color) -> text (or a glyph) in the theme in use
    ret.setRet(colorValue(uiInk(vm.colorArg(args, "theme.ink"))))
  themeT.reg("glow") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## theme.glow(color) -> a translucent highlight in the theme in use
    ret.setRet(colorValue(uiGlow(vm.colorArg(args, "theme.glow"))))
  rawSet(base, vstr("theme"), vtable(themeT))
