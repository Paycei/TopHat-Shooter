## The script-facing engine controls (MODDING.md "Camera and time",
## "Commands"): the `camera` and `time` libraries and register.command.
##
## HIGH layer: installed last by the loader. What the game reads lives on the
## run (Game.modWorld: zoom, centre, follow, clocks; reset with every new run)
## and in mod_registry (the commands, the camera's easing).

import std/[strutils, math]
import raylib
import ../types, ../d_systems, ../render_context
import lua_bridge, mod_hooks, mod_reflect, mod_api, mod_registry

const CommandKeys = ["name", "help", "run"]

proc runGameOrError(vm: VM, what: string): Game =
  result = modCtx.game
  if result.isNil or modCtx.inPvP: vm.runtimeError(what & " needs a run in progress (not PvP)")

proc finite(vm: VM, v: ScriptValue, what: string): float32 =
  if v.kind == vkNumber and abs(v.n) < 1.0e9: return v.n.float32
  vm.runtimeError(what & " must be a finite number")

proc camTarget(g: Game): tuple[x, y: float32] =
  let w = g.modWorld
  if w.camZoom <= 0: (g.screenWidth.float32 / 2, g.screenHeight.float32 / 2)
  else: (w.camCurX, w.camCurY)

proc installModEngine*(base: ScriptTable) =
  # ---- camera
  let camT = newScriptTable()
  camT.reg("follow") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## camera.follow(on [, lerp]): keep the player centred (lerp = how fast it
    ## catches up, per second; 0 snaps)
    let g = vm.runGameOrError("camera.follow")
    g.modWorld.camFollow = truthy(arg(args, 0))
    if arg(args, 1).kind != vkNil:
      g.modWorld.camLerp = max(0'f32, vm.finite(arg(args, 1), "camera.follow's lerp"))
    if g.modWorld.camZoom <= 0: g.modWorld.camZoom = 1
  camT.reg("reset") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## camera.reset(): the whole arena again
    let g = vm.runGameOrError("camera.reset")
    g.modWorld.camZoom = 0
    g.modWorld.camFollow = false
    g.modWorld.camCurX = 0
    g.modWorld.camCurY = 0
  camT.reg("toScreen") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## camera.toScreen(x, y) -> the screen point (virtual pixels) an arena point is drawn at
    let p = worldToVirtual(Vector2(x: vm.checkNum(args, 0, "toScreen").float32,
                                   y: vm.checkNum(args, 1, "toScreen").float32))
    ret.setRet([vnum(p.x.float64), vnum(p.y.float64)])
  camT.reg("toWorld") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## camera.toWorld(x, y) -> the arena point under a screen point
    let s = getWorldCamScale()
    ret.setRet([vnum(((vm.checkNum(args, 0, "toWorld").float32 - getWorldCamOffsetX()) / s).float64),
                vnum(((vm.checkNum(args, 1, "toWorld").float32 - getWorldCamOffsetY()) / s).float64)])
  camT.meta = newScriptTable()
  rawSet(camT.meta, vstr("__index"), vnative(newNative("camera_index",
    proc (vm: VM, args: openArray[ScriptValue], ret: var RetVals) =
      let name = keyName(arg(args, 1))
      let g = modCtx.game
      case name
      of "zoom": ret.setRet(vnum(if g.isNil or g.modWorld.camZoom <= 0: 1.0 else: g.modWorld.camZoom.float64))
      of "x", "y":
        if g.isNil: ret.setRet(NilValue)
        else:
          let c = camTarget(g)
          ret.setRet(vnum((if name == "x": c.x else: c.y).float64))
      of "following": ret.setRet(vbool(not g.isNil and g.modWorld.camFollow))
      else: ret.setRet(NilValue))))
  rawSet(camT.meta, vstr("__newindex"), vnative(newNative("camera_newindex",
    proc (vm: VM, args: openArray[ScriptValue], ret: var RetVals) =
      let name = keyName(arg(args, 1))
      let g = vm.runGameOrError("camera." & name)
      let v = vm.finite(arg(args, 2), "camera." & name)
      case name
      of "zoom":
        if g.modWorld.camZoom <= 0:
          (g.modWorld.camX, g.modWorld.camY) = camTarget(g)
        g.modWorld.camZoom = clamp(v, 1'f32, 3'f32)
      of "x", "y":
        if g.modWorld.camZoom <= 0:
          g.modWorld.camZoom = 1
          (g.modWorld.camX, g.modWorld.camY) = camTarget(g)
        if name == "x": g.modWorld.camX = v else: g.modWorld.camY = v
        g.modWorld.camFollow = false
      else: vm.runtimeError("camera." & name & " cannot be set (zoom, x, y)"))))
  rawSet(base, vstr("camera"), vtable(camT))

  # ---- time
  let timeT = newScriptTable()
  timeT.reg("hitstop") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## time.hitstop(seconds [, scale = 0.05]): freeze the world for a beat (real seconds)
    let g = vm.runGameOrError("time.hitstop")
    triggerHitStop(g.dopamine.slowMotion, clamp(vm.checkNum(args, 0, "hitstop").float32, 0'f32, 2'f32),
                   clamp(vm.optNum(args, 1, "hitstop", 0.05).float32, 0'f32, 1'f32))
  timeT.reg("slowmo") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## time.slowmo(seconds, scale [, ramp = false]): slow motion (real seconds),
    ## easing back to normal over it with ramp
    let g = vm.runGameOrError("time.slowmo")
    activateCustomSlowMo(g.dopamine.slowMotion, vm.checkNum(args, 1, "slowmo").float32,
                         clamp(vm.checkNum(args, 0, "slowmo").float32, 0'f32, 10'f32), truthy(arg(args, 2)))
  timeT.meta = newScriptTable()
  rawSet(timeT.meta, vstr("__index"), vnative(newNative("time_index",
    proc (vm: VM, args: openArray[ScriptValue], ret: var RetVals) =
      let g = modCtx.game
      case keyName(arg(args, 1))
      of "scale": ret.setRet(vnum(if g.isNil: 1.0 else: modWorldTimeScale(g).float64))
      of "enemyScale":
        ret.setRet(vnum(if g.isNil or not g.modWorld.enemyTimeSet: 1.0
                        else: g.modWorld.enemyTimeScale.float64))
      else: ret.setRet(NilValue))))
  rawSet(timeT.meta, vstr("__newindex"), vnative(newNative("time_newindex",
    proc (vm: VM, args: openArray[ScriptValue], ret: var RetVals) =
      let name = keyName(arg(args, 1))
      let g = vm.runGameOrError("time." & name)
      let v = vm.finite(arg(args, 2), "time." & name)
      case name
      of "scale": g.modWorld.timeScale = clamp(v, 0.1'f32, 2'f32)
      of "enemyScale":
        g.modWorld.enemyTimeScale = clamp(v, 0'f32, 2'f32)
        g.modWorld.enemyTimeSet = true
      else: vm.runtimeError("time." & name & " cannot be set (scale, enemyScale)"))))
  rawSet(base, vstr("time"), vtable(timeT))

  # ---- register.command
  let registerT = rawGetStr(base, "register").tbl
  registerT.reg("command") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## register.command{name = "souls", help = {en = "Shows your souls", es = "..."},
    ##   run = function(args) return "You have " .. mod.storage.souls .. " souls" end}
    ## -- a word the Help terminal runs (on the desktop); args are the words after it
    let owner = vm.requireLoading("register.command")
    let t = vm.checkTable(args, 0, "register.command")
    vm.checkKeys(t, CommandKeys, "register.command")
    let nv = rawGetStr(t, "name")
    if nv.kind != vkString or nv.str.s.len == 0:
      vm.runtimeError("register.command needs a name")
    let name = nv.str.s.toLowerAscii
    for c in name:
      if c notin {'a'..'z', '0'..'9', '_', '-', '.'}:
        vm.runtimeError("register.command: a name is one word (letters, digits, _ - .), got \"" & name & "\"")
    if findCommand(name) >= 0: vm.runtimeError("register.command: '" & name & "' is already a mod command")
    var c = CommandDef(name: name, owner: owner)
    (c.helpEn, c.helpEs) = vm.textPair(rawGetStr(t, "help"), "register.command.help")
    c.run = rawGetStr(t, "run")
    if c.run.kind notin {vkFunction, vkNative}: vm.runtimeError("register.command needs run = function(args)")
    commandDefs.add(c)
    ret.setRet(vstr(name))
