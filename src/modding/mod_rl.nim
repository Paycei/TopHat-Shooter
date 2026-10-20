## rl.* and rl.gl.*: raylib and rlgl, the libraries the game draws, plays sound
## and reads input with, whole, for scripts (see MODDING.md, "raylib").
##
##   rl.drawCircle(100, 100, 20, rl.Red)          -- inside a draw hook
##   local tex = rl.loadTexture(mod.path("art/ship.png"))
##   rl.drawTexture(tex, {x = 10, y = 20}, rl.White)
##
## Every exported proc of naylib's raylib and rlgl modules is bound like the
## game's own callable procs (mod_mixin_bind's bindCallables): overloads are
## tried in order, vectors / rectangles / colours are tables, and textures,
## fonts, sounds, models... are handles (mod_deep): one a script loads is its
## own and unloads once dropped (after the frame), one from the game or from
## raylib itself is a view. Left out: what only the game may do, the window
## and audio device's lifecycle and the frame itself (the game opens, draws
## and closes those), and the callback setters (scripts cannot be C callbacks).

import mod_mixin_bind   # (raylib and rlgl come in through bindCallables' own imports)

bindCallables(currentSourcePath(), ["../../vendor/naylib/src/raylib.nim", "../../vendor/naylib/src/rlgl.nim"],
  skip = @["initWindow", "closeWindow", "beginDrawing", "endDrawing", "swapScreenBuffer",
          "pollInputEvents", "initAudioDevice", "closeAudioDevice", "rlglInit", "rlglClose",
          "setTraceLogCallback", "setLoadFileDataCallback", "setSaveFileDataCallback",
          "setLoadFileTextCallback", "setSaveFileTextCallback", "setAudioStreamCallback",
          "attachAudioStreamProcessor", "detachAudioStreamProcessor",
          "attachAudioMixedProcessor", "detachAudioMixedProcessor"])

proc installModRl*(base: ScriptTable) =
  ## `rl` (= engine.raylib) with `rl.gl` (= engine.rlgl), rl.unload and the
  ## colour constants. After installModMixin, which makes the engine tables.
  let engineV = rawGetStr(base, "engine")
  if engineV.kind != vkTable: return
  let rlV = rawGetStr(engineV.tbl, "raylib")
  let rlT = if rlV.kind == vkTable: rlV.tbl else: newScriptTable()
  let glV = rawGetStr(engineV.tbl, "rlgl")
  if glV.kind == vkTable: rawSet(rlT, vstr("gl"), glV)
  rlT.reg("unload") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## rl.unload(handle): unload a resource you loaded now (after this frame)
    ## instead of when it is dropped -> true; false for a view (the game's).
    ret.setRet(vbool(unloadHandle(arg(args, 0))))
  for (name, c) in [("LightGray", LightGray), ("Gray", Gray), ("DarkGray", DarkGray),
                    ("Yellow", Yellow), ("Gold", Gold), ("Orange", Orange), ("Pink", Pink),
                    ("Red", Red), ("Maroon", Maroon), ("Green", Green), ("Lime", Lime),
                    ("DarkGreen", DarkGreen), ("SkyBlue", SkyBlue), ("Blue", Blue),
                    ("DarkBlue", DarkBlue), ("Purple", Purple), ("Violet", Violet),
                    ("DarkPurple", DarkPurple), ("Beige", Beige), ("Brown", Brown),
                    ("DarkBrown", DarkBrown), ("White", White), ("Black", Black),
                    ("Blank", Blank), ("Magenta", Magenta), ("RayWhite", RayWhite)]:
    rawSet(rlT, vstr(name), nimToScript(c, "rl." & name))
  rawSet(base, vstr("rl"), vtable(rlT))
