## The script-facing API of the content registries (MODDING.md "Statuses",
## "Difficulty", "More content"): register.status and the status methods of
## enemies and the player, difficulty.scale, and the registries M3 adds
## (consumables, shop items, patches, survival events, achievements).
##
## HIGH layer like mod_api: the loader installs it after mod_world2d. What
## gameplay reads (the registries, their call-site helpers) lives in the LOW
## module mod_registry. Every new table here is strict.

import std/[strutils, math]
import raylib
import ../types, ../effects

import lua_bridge, mod_hooks, mod_reflect, mod_api, mod_registry

const
  StatusKeys = ["id", "name", "color", "icon", "maxStacks", "duration", "tickInterval", "modifiers",
                "onApply", "onTick", "onExpire", "draw"]
  ModifierKeys = ["speed", "damageTaken", "damageDealt"]
  ApplyKeys = ["duration", "stacks", "magnitude"]
  BuiltinEnemyStatuses = ["fire", "poison", "slow", "frost"]

proc finiteNum(vm: VM, v: ScriptValue, what: string): float32 =
  if v.kind == vkNumber and abs(v.n) < 1.0e9: return v.n.float32
  vm.runtimeError(what & " must be a finite number")

proc fnOf(vm: VM, t: ScriptTable, key, what: string): ScriptValue =
  result = rawGetStr(t, key)
  if result.kind notin {vkNil, vkFunction, vkNative}:
    vm.runtimeError(what & "." & key & " must be a function")

# --------------------------------------------------------------- statuses ----
proc statusKey(vm: VM, name, fname: string): int =
  result = findStatus(name)
  if result < 0:
    vm.runtimeError(fname & ": unknown status '" & name & "' (" & BuiltinEnemyStatuses.join(", ") &
                    " or one from register.status)")

type ApplyOpts = tuple[duration, magnitude: float32, stacks: int, hasDuration, hasMagnitude: bool]

proc readApply(vm: VM, v: ScriptValue, fname: string): ApplyOpts =
  result = (-1'f32, 1'f32, 1, false, false)
  if v.kind == vkNil: return
  if v.kind != vkTable: vm.runtimeError(fname & ": options must be a table")
  vm.checkKeys(v.tbl, ApplyKeys, fname)
  let d = rawGetStr(v.tbl, "duration")
  if d.kind != vkNil:
    result.duration = vm.finiteNum(d, fname & ".duration")
    result.hasDuration = true
  let m = rawGetStr(v.tbl, "magnitude")
  if m.kind != vkNil:
    result.magnitude = vm.finiteNum(m, fname & ".magnitude")
    result.hasMagnitude = true
  let s = rawGetStr(v.tbl, "stacks")
  if s.kind != vkNil: result.stacks = clamp(int(vm.finiteNum(s, fname & ".stacks")), 1, 1000)

proc statusTable(inst: ModStatusInst): ScriptValue =
  let t = newScriptTable()
  rawSet(t, vstr("stacks"), vnum(inst.stacks.int))
  rawSet(t, vstr("remaining"), vnum(inst.remaining.float64))
  rawSet(t, vstr("duration"), vnum(inst.duration.float64))
  rawSet(t, vstr("magnitude"), vnum(inst.magnitude.float64))
  vtable(t)

proc installStatuses(base: ScriptTable) =
  let registerT = rawGetStr(base, "register").tbl
  registerT.reg("status") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## local SOUL = register.status{id = "soulBurn", color = "#a040ff", maxStacks = 5,
    ##   duration = 4, tickInterval = 0.5, modifiers = {speed = -0.1, damageTaken = 0.15},
    ##   onApply = fn(target, stacks, magnitude), onTick = fn(target, stacks, magnitude),
    ##   onExpire = fn(target), draw = fn(target, x, y, stacks)}
    let owner = vm.requireLoading("register.status")
    let t = vm.checkTable(args, 0, "register.status")
    vm.checkKeys(t, StatusKeys, "register.status")
    let key = mods[owner].id & ":" & vm.checkName(t, "register.status")
    if findStatus(key) >= 0: vm.runtimeError("register.status: '" & key & "' is already registered")
    var d = StatusDef(key: key, owner: owner, color: Color(r: 200, g: 120, b: 255, a: 255),
                      maxStacks: 1, duration: 3)
    (d.nameEn, d.nameEs) = vm.textPair(rawGetStr(t, "name"), "register.status.name")
    if d.nameEn.len == 0: d.nameEn = key.split(':')[1]
    let c = rawGetStr(t, "color")
    if c.kind != vkNil: d.color = parseColor(vm, c, "register.status.color")
    let ic = rawGetStr(t, "icon")
    if ic.kind != vkNil: d.iconTex = vm.textureId(ic, "register.status.icon")
    let ms = rawGetStr(t, "maxStacks")
    if ms.kind != vkNil: d.maxStacks = clamp(int(vm.finiteNum(ms, "register.status.maxStacks")), 1, 1000)
    let du = rawGetStr(t, "duration")
    if du.kind != vkNil: d.duration = vm.finiteNum(du, "register.status.duration")
    let ti = rawGetStr(t, "tickInterval")
    if ti.kind != vkNil: d.tickInterval = max(0'f32, vm.finiteNum(ti, "register.status.tickInterval"))
    if d.tickInterval > 0 and d.tickInterval < 0.05: d.tickInterval = 0.05
    let mods2 = rawGetStr(t, "modifiers")
    if mods2.kind == vkTable:
      vm.checkKeys(mods2.tbl, ModifierKeys, "register.status.modifiers")
      for (field, dest) in [("speed", addr d.speed), ("damageTaken", addr d.damageTaken),
                            ("damageDealt", addr d.damageDealt)]:
        let v = rawGetStr(mods2.tbl, field)
        if v.kind != vkNil: dest[] = vm.finiteNum(v, "register.status.modifiers." & field)
    elif mods2.kind != vkNil: vm.runtimeError("register.status.modifiers must be a table")
    for (field, dest) in [("onApply", addr d.onApply), ("onTick", addr d.onTick),
                          ("onExpire", addr d.onExpire), ("draw", addr d.draw)]:
      dest[] = vm.fnOf(t, field, "register.status")
    addStatusDef(d)
    ret.setRet(vstr(key))

  # ---- enemy:applyStatus / status / clearStatus
  enemyMethods.reg("applyStatus") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## e:applyStatus(name [, {duration, stacks, magnitude}]) -> true if applied.
    ## The game's own effects by name: "fire" and "poison" (magnitude = damage
    ## per second), "slow" (magnitude 0-1, timed) and "frost" (a lasting chill).
    let e = unwrapEnemy(arg(args, 0))
    if e.isNil: vm.runtimeError("enemy:applyStatus() needs an enemy (call it with ':')")
    discard vm.requireRunGame()
    let name = vm.checkStr(args, 1, "applyStatus")
    let o = vm.readApply(arg(args, 2), "applyStatus")
    let dur = if o.hasDuration: o.duration else: 3'f32
    case name
    of "fire":
      applyEffect(e, etFire, (if o.hasMagnitude: o.magnitude else: 1'f32), dur, "mod")
      ret.setRet(TrueValue)
    of "poison":
      applyEffect(e, etPoison, (if o.hasMagnitude: o.magnitude else: 1'f32), dur, "mod")
      ret.setRet(TrueValue)
    of "slow":
      applySlow(e, clamp((if o.hasMagnitude: o.magnitude else: 0.4'f32), 0'f32, 0.95'f32), dur)
      ret.setRet(TrueValue)
    of "frost":
      applyFrostChill(e, clamp((if o.hasMagnitude: o.magnitude else: 0.25'f32), 0'f32, 0.95'f32))
      ret.setRet(TrueValue)
    else:
      discard vm.statusKey(name, "enemy:applyStatus")
      ret.setRet(vbool(applyModStatus(e, name, o.duration, o.magnitude, o.stacks)))
  enemyMethods.reg("status") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## e:status(name) -> {stacks, remaining, duration, magnitude} or nil
    let e = unwrapEnemy(arg(args, 0))
    if e.isNil: vm.runtimeError("enemy:status() needs an enemy (call it with ':')")
    let name = vm.checkStr(args, 1, "status")
    case name
    of "fire", "poison":
      let ef = e.activeEffects[if name == "fire": etFire else: etPoison].primary
      if not ef.isActive or ef.remainingDuration <= 0: ret.setRet(NilValue)
      else:
        ret.setRet(statusTable(ModStatusInst(key: name, stacks: 1, remaining: ef.remainingDuration,
                                             duration: ef.maxDuration, magnitude: ef.damagePerSec)))
    of "slow":
      if e.slowTimer <= 0: ret.setRet(NilValue)
      else: ret.setRet(statusTable(ModStatusInst(key: name, stacks: 1, remaining: e.slowTimer,
                                                 magnitude: e.slowAmount)))
    of "frost":
      if e.frostSlowAmount <= 0: ret.setRet(NilValue)
      else: ret.setRet(statusTable(ModStatusInst(key: name, stacks: 1, magnitude: e.frostSlowAmount)))
    else:
      discard vm.statusKey(name, "enemy:status")
      let i = statusPos(e, name)
      ret.setRet(if i < 0: NilValue else: statusTable(e.modStatuses[i]))
  enemyMethods.reg("clearStatus") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    let e = unwrapEnemy(arg(args, 0))
    if e.isNil: vm.runtimeError("enemy:clearStatus() needs an enemy (call it with ':')")
    let name = vm.checkStr(args, 1, "clearStatus")
    case name
    of "fire", "poison":
      let et = if name == "fire": etFire else: etPoison
      e.activeEffects[et].primary.isActive = false
      e.activeEffects[et].primary.remainingDuration = 0
      e.activeEffects[et].fallback.remainingDuration = 0
    of "slow":
      e.slowTimer = 0
      e.slowAmount = 0
    of "frost": e.frostSlowAmount = 0
    else:
      discard vm.statusKey(name, "enemy:clearStatus")
      clearModStatus(e, name)

  # ---- player:applyStatus / status / clearStatus
  playerMethods.reg("applyStatus") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## player:applyStatus(name [, {duration, stacks, magnitude}]); "poison"
    ## (magnitude = damage per second) is the game's own.
    let p = unwrapPlayer(arg(args, 0))
    if p.isNil: vm.runtimeError("player:applyStatus() needs the player (call it with ':')")
    discard vm.requireRunGame()
    let name = vm.checkStr(args, 1, "applyStatus")
    let o = vm.readApply(arg(args, 2), "applyStatus")
    if name == "poison":
      p.poisonTimer = max(p.poisonTimer, if o.hasDuration: o.duration else: 3'f32)
      p.poisonDamage = if o.hasMagnitude: max(0'f32, o.magnitude) else: 0.5'f32
      ret.setRet(TrueValue)
      return
    discard vm.statusKey(name, "player:applyStatus")
    ret.setRet(vbool(applyModStatus(p, name, o.duration, o.magnitude, o.stacks)))
  playerMethods.reg("status") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    let p = unwrapPlayer(arg(args, 0))
    if p.isNil: vm.runtimeError("player:status() needs the player (call it with ':')")
    let name = vm.checkStr(args, 1, "status")
    if name == "poison":
      ret.setRet(if p.poisonTimer <= 0: NilValue
                 else: statusTable(ModStatusInst(key: name, stacks: 1, remaining: p.poisonTimer,
                                                 magnitude: p.poisonDamage)))
      return
    discard vm.statusKey(name, "player:status")
    let i = statusPos(p, name)
    ret.setRet(if i < 0: NilValue else: statusTable(p.modStatuses[i]))
  playerMethods.reg("clearStatus") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    let p = unwrapPlayer(arg(args, 0))
    if p.isNil: vm.runtimeError("player:clearStatus() needs the player (call it with ':')")
    let name = vm.checkStr(args, 1, "clearStatus")
    if name == "poison":
      p.poisonTimer = 0
      return
    discard vm.statusKey(name, "player:clearStatus")
    clearModStatus(p, name)

  let statusesT = newScriptTable()
  statusesT.reg("list") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    var names = @BuiltinEnemyStatuses
    for d in statusDefs: names.add(d.key)
    ret.setRet(namesTable(names))
  rawSet(base, vstr("statuses"), vtable(statusesT))

# ------------------------------------------------------------- difficulty ----
proc installDifficulty(base: ScriptTable) =
  let diffT = newScriptTable()
  diffT.reg("scale") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## difficulty.scale{enemyHp = 1.5, enemyDamage = 1.2, enemySpeed = 1, spawnPace = 1.3,
    ##   eliteChance = 2, bossCooldown = 0.8} -- multipliers on top of the profile's
    ##   difficulty, for this run (every run starts at 1: set them in runStart)
    discard vm.requireRunGame()
    let t = vm.checkTable(args, 0, "difficulty.scale")
    var names: seq[string]
    for l in DifficultyLever: names.add($l)
    vm.checkKeys(t, names, "difficulty.scale")
    for l in DifficultyLever:
      let v = rawGetStr(t, $l)
      if v.kind != vkNil:
        modDifficultyScale[ord(l)] = clamp(vm.finiteNum(v, "difficulty.scale." & $l), 0.05'f32, 20'f32)
  diffT.reg("get") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## difficulty.get() -> {profile = "gdHard", enemyHp = .., ...} (the scale in force)
    let t = newScriptTable()
    rawSet(t, vstr("profile"), vstr($currentDifficulty))
    for l in DifficultyLever: rawSet(t, vstr($l), vnum(modDifficultyScale[ord(l)].float64))
    ret.setRet(vtable(t))
  rawSet(base, vstr("difficulty"), vtable(diffT))


# =========================================================== M3 registries ====
const
  ConsumableKeys = ["id", "name", "color", "icon", "weight", "modes", "stats", "onPickup"]
  ShopItemKeys = ["id", "name", "description", "icon", "color", "cost", "costMult", "maxBuys",
                  "modes", "minWave", "stats", "onBuy"]
  PatchKeys = ["id", "name", "description", "icon", "color", "weight", "minFloor", "stats",
               "onInstall", "update"]
  EventKeys = ["id", "name", "hint", "color", "weights", "duration", "warmup", "reward", "onStart",
               "update", "onFinish", "tracker", "fraction"]
  WeightKeys = ["boot", "runtime", "overload", "panic"]
  AdvancementKeys = ["id", "name", "description", "icon", "color", "goal", "hidden"]

proc readStats*(vm: VM, v: ScriptValue, what: string): seq[StatDelta] =
  ## The `stats` DSL: {damage = "+10%", maxHp = 2, fireRate = "x0.95", walls = "=10"}.
  if v.kind == vkNil: return
  if v.kind != vkTable: vm.runtimeError(what & ".stats must be a table {field = change}")
  for (k, x) in pairsCursor(v.tbl):
    if k.kind != vkString: vm.runtimeError(what & ".stats keys must be player field names")
    var err = ""
    let d = parseStatDelta(k.str.s, x, err)
    if err.len > 0: vm.runtimeError(what & ": " & err)
    result.add(d)

proc readIcon(vm: VM, t: ScriptTable, what: string, tex: var int, fn: var ScriptValue) =
  ## icon = a texture (or file name) or a function drawing it.
  let ic = rawGetStr(t, "icon")
  case ic.kind
  of vkNil: discard
  of vkFunction, vkNative: fn = ic
  else: tex = vm.textureId(ic, what & ".icon")

proc colorOr(vm: VM, t: ScriptTable, what: string, def: Color): Color =
  let c = rawGetStr(t, "color")
  if c.kind == vkNil: def else: parseColor(vm, c, what & ".color")

proc numOr(vm: VM, t: ScriptTable, key, what: string, def: float32): float32 =
  let v = rawGetStr(t, key)
  if v.kind == vkNil: def else: vm.finiteNum(v, what & "." & key)

proc installRegistries(base: ScriptTable) =
  let registerT = rawGetStr(base, "register").tbl

  registerT.reg("consumable") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## local MANA = register.consumable{id = "mana", name = "Mana", color = "#4080ff",
    ##   weight = 6, modes = {"wave"}, stats = {damage = "+5%"}, onPickup = fn(player, game, x, y)}
    let owner = vm.requireLoading("register.consumable")
    let t = vm.checkTable(args, 0, "register.consumable")
    vm.checkKeys(t, ConsumableKeys, "register.consumable")
    let key = mods[owner].id & ":" & vm.checkName(t, "register.consumable")
    if findConsumable(key) >= 0: vm.runtimeError("register.consumable: '" & key & "' is already registered")
    var d = ConsumableDef(key: key, owner: owner, weight: 5)
    (d.nameEn, d.nameEs) = vm.textPair(rawGetStr(t, "name"), "register.consumable.name")
    if d.nameEn.len == 0: d.nameEn = key.split(':')[1]
    d.color = vm.colorOr(t, "register.consumable", Color(r: 120, g: 200, b: 255, a: 255))
    vm.readIcon(t, "register.consumable", d.iconTex, d.icon)
    d.weight = max(0'f32, vm.numOr(t, "weight", "register.consumable", 5))
    d.modes = vm.parseModes(rawGetStr(t, "modes"))
    d.stats = vm.readStats(rawGetStr(t, "stats"), "register.consumable")
    d.onPickup = vm.fnOf(t, "onPickup", "register.consumable")
    addConsumableDef(d)
    ret.setRet(vstr(key))

  registerT.reg("shopItem") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## local CORE = register.shopItem{id = "core", name = "Spare Core", description = "+1 wall",
    ##   cost = 12, costMult = 1.5, maxBuys = 5, modes = {"wave"}, minWave = 3,
    ##   stats = {walls = 1}, onBuy = fn(player, game, bought)}
    let owner = vm.requireLoading("register.shopItem")
    let t = vm.checkTable(args, 0, "register.shopItem")
    vm.checkKeys(t, ShopItemKeys, "register.shopItem")
    let key = mods[owner].id & ":" & vm.checkName(t, "register.shopItem")
    if findShopItem(key) >= 0: vm.runtimeError("register.shopItem: '" & key & "' is already registered")
    var d = ShopItemDef(key: key, owner: owner, cost: 10, costMult: 1.8)
    (d.nameEn, d.nameEs) = vm.textPair(rawGetStr(t, "name"), "register.shopItem.name")
    if d.nameEn.len == 0: d.nameEn = key.split(':')[1]
    (d.descEn, d.descEs) = vm.textPair(rawGetStr(t, "description"), "register.shopItem.description")
    d.color = vm.colorOr(t, "register.shopItem", Color(r: 120, g: 220, b: 160, a: 255))
    vm.readIcon(t, "register.shopItem", d.iconTex, d.icon)
    d.cost = clamp(int(vm.numOr(t, "cost", "register.shopItem", 10)), 0, 1_000_000)
    d.costMult = clamp(vm.numOr(t, "costMult", "register.shopItem", 1.8), 1'f32, 10'f32)
    d.maxBuys = clamp(int(vm.numOr(t, "maxBuys", "register.shopItem", 0)), 0, 1000)
    d.minWave = max(0, int(vm.numOr(t, "minWave", "register.shopItem", 0)))
    d.modes = vm.parseModes(rawGetStr(t, "modes"))
    d.stats = vm.readStats(rawGetStr(t, "stats"), "register.shopItem")
    d.onBuy = vm.fnOf(t, "onBuy", "register.shopItem")
    addShopItemDef(d)
    ret.setRet(vstr(key))

  registerT.reg("patch") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## local WARD = register.patch{id = "ward", name = "Soul Ward", description = "...",
    ##   color = "#a040ff", weight = 1, minFloor = 2, stats = {maxHp = 2},
    ##   onInstall = fn(player, game), update = fn(player, dt, game)}
    let owner = vm.requireLoading("register.patch")
    let t = vm.checkTable(args, 0, "register.patch")
    vm.checkKeys(t, PatchKeys, "register.patch")
    let key = mods[owner].id & ":" & vm.checkName(t, "register.patch")
    if findPatch(key) >= 0: vm.runtimeError("register.patch: '" & key & "' is already registered")
    var d = PatchDef(key: key, owner: owner, weight: 1, minFloor: 1)
    (d.nameEn, d.nameEs) = vm.textPair(rawGetStr(t, "name"), "register.patch.name")
    if d.nameEn.len == 0: d.nameEn = key.split(':')[1]
    (d.descEn, d.descEs) = vm.textPair(rawGetStr(t, "description"), "register.patch.description")
    d.color = vm.colorOr(t, "register.patch", Color(r: 170, g: 140, b: 255, a: 255))
    vm.readIcon(t, "register.patch", d.iconTex, d.icon)
    d.weight = max(0'f32, vm.numOr(t, "weight", "register.patch", 1))
    d.minFloor = max(1, int(vm.numOr(t, "minFloor", "register.patch", 1)))
    d.stats = vm.readStats(rawGetStr(t, "stats"), "register.patch")
    d.onInstall = vm.fnOf(t, "onInstall", "register.patch")
    d.update = vm.fnOf(t, "update", "register.patch")
    addPatchDef(d)
    ret.setRet(vstr(key))

  registerT.reg("survivalEvent") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## local STORM = register.survivalEvent{id = "storm", name = "Packet Storm", hint = "...",
    ##   color = "#40c0ff", weights = {boot = 0, runtime = 20, overload = 25, panic = 25},
    ##   duration = 20, warmup = 2, reward = "sctStandard" | false,
    ##   onStart = fn(ev, game), update = fn(ev, game, dt) -> "success" | "fail" | nil,
    ##   onFinish = fn(ev, game, success), tracker = fn(ev, game) -> text,
    ##   fraction = fn(ev, game) -> 0..1}
    let owner = vm.requireLoading("register.survivalEvent")
    let t = vm.checkTable(args, 0, "register.survivalEvent")
    vm.checkKeys(t, EventKeys, "register.survivalEvent")
    let key = mods[owner].id & ":" & vm.checkName(t, "register.survivalEvent")
    if findSurvivalEvent(key) >= 0: vm.runtimeError("register.survivalEvent: '" & key & "' is already registered")
    var d = SurvivalEventDef(key: key, owner: owner, duration: 20, warmup: 2, reward: ord(sctStandard),
                             weights: [10'f32, 10, 10, 10])
    (d.nameEn, d.nameEs) = vm.textPair(rawGetStr(t, "name"), "register.survivalEvent.name")
    if d.nameEn.len == 0: d.nameEn = key.split(':')[1]
    (d.hintEn, d.hintEs) = vm.textPair(rawGetStr(t, "hint"), "register.survivalEvent.hint")
    d.color = vm.colorOr(t, "register.survivalEvent", Color(r: 120, g: 200, b: 255, a: 255))
    let w = rawGetStr(t, "weights")
    if w.kind == vkTable:
      vm.checkKeys(w.tbl, WeightKeys, "register.survivalEvent.weights")
      for i, name in WeightKeys:
        let v = rawGetStr(w.tbl, name)
        d.weights[i] = if v.kind == vkNil: 0'f32 else: max(0'f32, vm.finiteNum(v, "weights." & name))
    elif w.kind != vkNil: vm.runtimeError("register.survivalEvent.weights must be a table")
    d.duration = max(0'f32, vm.numOr(t, "duration", "register.survivalEvent", 20))
    d.warmup = max(0'f32, vm.numOr(t, "warmup", "register.survivalEvent", 2))
    let rw = rawGetStr(t, "reward")
    case rw.kind
    of vkNil: discard
    of vkBool:
      if not rw.b: d.reward = -1
    of vkString:
      var tier: SurvivalCacheTier
      try: tier = parseEnum[SurvivalCacheTier](rw.str.s)
      except ValueError:
        vm.runtimeError("register.survivalEvent.reward: sctMinor, sctStandard, sctRare, sctKernel or false")
      d.reward = ord(tier)
    else: vm.runtimeError("register.survivalEvent.reward must be a cache tier name or false")
    for (field, dest) in [("onStart", addr d.onStart), ("update", addr d.update),
                          ("onFinish", addr d.onFinish), ("tracker", addr d.tracker),
                          ("fraction", addr d.fraction)]:
      dest[] = vm.fnOf(t, field, "register.survivalEvent")
    addSurvivalEventDef(d)
    ret.setRet(vstr(key))

  registerT.reg("advancement") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## local SLAYER = register.advancement{id = "slayer", name = "Soul Slayer",
    ##   description = "Raise 100 allies", goal = 100, hidden = false, color = "#a040ff"}
    let owner = vm.requireLoading("register.advancement")
    let t = vm.checkTable(args, 0, "register.advancement")
    vm.checkKeys(t, AdvancementKeys, "register.advancement")
    let key = mods[owner].id & ":" & vm.checkName(t, "register.advancement")
    if findAdvancement(key) >= 0: vm.runtimeError("register.advancement: '" & key & "' is already registered")
    var d = AdvancementDef(key: key, owner: owner, goal: 1)
    (d.nameEn, d.nameEs) = vm.textPair(rawGetStr(t, "name"), "register.advancement.name")
    if d.nameEn.len == 0: d.nameEn = key.split(':')[1]
    (d.descEn, d.descEs) = vm.textPair(rawGetStr(t, "description"), "register.advancement.description")
    d.color = vm.colorOr(t, "register.advancement", Color(r: 255, g: 210, b: 80, a: 255))
    var fn = NilValue
    vm.readIcon(t, "register.advancement", d.iconTex, fn)
    if fn.kind != vkNil: vm.runtimeError("register.advancement.icon must be a texture")
    d.goal = clamp(int(vm.numOr(t, "goal", "register.advancement", 1)), 1, 1_000_000_000)
    d.hidden = truthy(rawGetStr(t, "hidden"))
    addAdvancementDef(d)
    ret.setRet(vstr(key))

  # ---- advancements.* (the running mod's own, by id or full name)
  let advT = newScriptTable()
  proc advKey(vm: VM, args: openArray[ScriptValue], fname: string): string =
    let owner = vm.requireOwner("advancements." & fname)
    var key = vm.checkStr(args, 0, fname)
    if ':' notin key: key = mods[owner].id & ":" & key
    if findAdvancement(key) < 0: vm.argError(fname, 0, "no achievement '" & key & "' (register.advancement it)")
    if advancementDefs[findAdvancement(key)].owner != owner:
      vm.argError(fname, 0, "'" & key & "' belongs to another mod")
    key
  advT.reg("progress") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## advancements.progress(id [, amount = 1]) -> true when this unlocked it
    let key = vm.advKey(args, "progress")
    ret.setRet(vbool(advancementProgress(key, vm.optInt(args, 1, "progress", 1))))
  advT.reg("grant") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    let key = vm.advKey(args, "grant")
    ret.setRet(vbool(advancementProgress(key, advancementDefs[findAdvancement(key)].goal, absolute = true)))
  advT.reg("get") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## advancements.get(id) -> {progress, goal, unlocked}
    let key = vm.advKey(args, "get")
    let st = advancementState(key)
    let t = newScriptTable()
    rawSet(t, vstr("progress"), vnum(st.progress))
    rawSet(t, vstr("goal"), vnum(advancementDefs[findAdvancement(key)].goal))
    rawSet(t, vstr("unlocked"), vbool(st.unlocked))
    ret.setRet(vtable(t))
  rawSet(base, vstr("advancements"), vtable(advT))

  # ---- player:hasPatch
  playerMethods.reg("hasPatch") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## player:hasPatch("rrtOverclock" | "<mod id>:<id>")
    let p = unwrapPlayer(arg(args, 0))
    if p.isNil: vm.runtimeError("player:hasPatch() needs the player (call it with ':')")
    let name = vm.checkStr(args, 1, "hasPatch")
    let g = modCtx.game
    if ':' in name:
      var has = false
      if not g.isNil and not g.rogueliteRun.isNil:
        for rl in g.rogueliteRun.relics:
          if rl.relicType == rrtMod and rl.modKey == name: has = true
      ret.setRet(vbool(has))
    else:
      var pt: RogueliteRelicType
      try: pt = parseEnum[RogueliteRelicType](name)
      except ValueError: vm.argError("hasPatch", 1, "unknown patch '" & name & "'")
      ret.setRet(vbool(pt in p.patches))

proc installContentApi*(base: ScriptTable) =
  installStatuses(base)
  installDifficulty(base)
  installRegistries(base)
