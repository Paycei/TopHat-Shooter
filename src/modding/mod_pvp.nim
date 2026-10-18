## The script-facing API of PvP (MODDING.md "PvP" documents it for modders):
## the `match` object, register.pvpmode, and a PvP player's and bullet's extras.
##
## pvp_game fires the pvp* hooks (through mod_hooks' helpers) and carries out
## what the match does; this module fills in what scripts see. It sits HIGH in
## the dependency DAG like mod_api: only the loader imports it (installModPvP,
## after installModEngine), and it fills mod_hooks' pvp* seams.
##
## Rules it keeps:
##  * The host decides the match. Everything that changes it (bullets, damage,
##    teleports, the result, broadcasts) is refused on a client with an error
##    that says so; reading, drawing and match:request work everywhere.
##  * Nothing structural happens inside the game's loops: spawned bullets join
##    at the next safe point of the frame, messages are delivered at the next.
##  * Script values never go on the wire: match.data and message data travel as
##    JSON (plain data only, like run.data).

import std/strutils
import raylib
import ../types, ../particle_types, ../pvp_game, ../localization, ../network/network
import lua_bridge, mod_hooks, mod_reflect, mod_api

var matchMethods: ScriptTable

const
  PvPModeKeys = ["id", "name", "description", "settings", "onStart"]
  BulletKeys = ["x", "y", "vx", "vy", "owner", "damage", "radius", "lifetime", "color",
                "kind", "pierce"]
  MatchFields = ["isHost", "mode", "localPlayer", "time", "timeLeft", "live", "countdown",
                 "over", "teams", "width", "height", "playerCount", "settings", "data"]
  PvPBulletExtras = ["owner", "kind", "pierce"]

# ------------------------------------------------------------- helpers ----
proc selfMatch(vm: VM, args: openArray[ScriptValue], fname: string): PvPGameState =
  let m = unwrapMatch(arg(args, 0))
  if m.isNil:
    vm.runtimeError("match:" & fname & "() needs the match (call it with ':') and a PvP match in progress")
  if m != modCtx.match:
    vm.runtimeError("match:" & fname & "(): that match has ended")
  PvPGameState(m)

proc hostMatch(vm: VM, args: openArray[ScriptValue], fname: string): PvPGameState =
  ## A method that changes the match: the host's call alone.
  result = vm.selfMatch(args, fname)
  if not result.networkManager.isHost():
    vm.runtimeError("match:" & fname & "() changes the match, which only the host does " &
                    "(check match.isHost; a client asks the host with match:request)")

proc finite(vm: VM, v: ScriptValue, what: string): float32 =
  if v.kind == vkNumber and abs(v.n) < 1.0e9: return v.n.float32   # (NaN fails too)
  vm.runtimeError(what & " must be a finite number")

proc playerArg(vm: VM, pvp: PvPGameState, v: ScriptValue, what: string): int =
  ## A player of this match, as the object or its index (1-based) -> its slot.
  if v.kind == vkNumber:
    let n = int(vm.finite(v, what))
    if n < 1 or n > pvp.players.len:
      vm.runtimeError(what & ": no player " & $n & " (1 to " & $pvp.players.len & ")")
    return n - 1
  let p = unwrapPlayer(v)
  if p.isNil: vm.runtimeError(what & ": a player expected, got " & typeName(v))
  result = pvp.playerIndexOf(p)
  if result < 0: vm.runtimeError(what & ": not a player of this match")

proc optPlayerArg(vm: VM, pvp: PvPGameState, v: ScriptValue, what: string): int =
  if v.kind == vkNil: -1 else: vm.playerArg(pvp, v, what)

proc teamArg(vm: VM, v: ScriptValue, what: string): PvPTeam =
  ## "ptRed" or "red" (any case).
  let s = v.str.s
  for team in PvPTeam:
    if team == ptNone: continue
    if s == $team or cmpIgnoreCase(s, ($team)[2 .. ^1]) == 0: return team
  vm.runtimeError(what & ": unknown team '" & s & "' (red, blue, green, yellow, orange, purple)")

proc localText(vm: VM, v: ScriptValue, what: string): string =
  ## "Text" or {en = .., es = .., <mod language> = ..}, in this machine's language.
  if v.kind == vkTable and activeModLanguage.len > 0:
    let own = rawGetStr(v.tbl, activeModLanguage)
    if own.kind == vkString: return own.str.s
  let (en, es) = vm.textPair(v, what)
  pickText(en, es)

proc messageArgs(vm: VM, args: openArray[ScriptValue], fname: string): tuple[name, data: string] =
  result.name = vm.checkStr(args, 1, fname)
  if result.name.len == 0 or result.name.len > MaxModMsgName:
    vm.argError(fname, 1, "a message name is 1-" & $MaxModMsgName & " characters")
  result.data = scriptToJson(arg(args, 2))
  if result.data.len > MaxModMsgBytes:
    vm.argError(fname, 2, "the data is too large to send (" & $result.data.len & " bytes as JSON, " &
                $MaxModMsgBytes & " max)")

proc settingsTable(pvp: PvPGameState): ScriptValue =
  ## match.settings: the match's rules, as the lobby names them (a copy).
  let c = pvp.config
  let t = newScriptTable()
  rawSet(t, vstr("hp"), vnum(c.startHp.float64))
  rawSet(t, vstr("speed"), vnum(c.startSpeed.float64))
  rawSet(t, vstr("damage"), vnum(c.startDamage.float64))
  rawSet(t, vstr("fireRate"), vnum(c.fireRate.float64))
  rawSet(t, vstr("bulletSpeed"), vnum(c.bulletSpeed.float64))
  rawSet(t, vstr("bulletSize"), vnum(c.bulletRadius.float64))
  rawSet(t, vstr("walls"), vnum(c.startWalls))
  rawSet(t, vstr("killLimit"), vnum(c.killLimit))
  rawSet(t, vstr("respawn"), vnum(c.respawnTime.float64))
  rawSet(t, vstr("timeLimit"), vnum(c.timeLimit.float64))
  rawSet(t, vstr("packages"), vbool(c.pickupsEnabled))
  rawSet(t, vstr("teams"), vbool(pvp.teamsEnabled))
  vtable(t)

# ---------------------------------------------------------- seams (mod_api) ----
proc pvpPlayerField(p: Player, name: string, found: var bool): ScriptValue {.nimcall.} =
  ## A PvP player's extras: index (1-based), name, deaths, streak, connected,
  ## alive, isLocal. Only for the players of the match on screen.
  found = false
  result = NilValue
  if name notin PvPPlayerExtras or modCtx.match.isNil: return
  let pvp = PvPGameState(modCtx.match)
  let i = pvp.playerIndexOf(p)
  if i < 0: return
  found = true
  case name
  of "index": result = vnum(i + 1)
  of "name": result = vstr(pvp.playerName(i))
  of "deaths": result = vnum(pvp.stats[i].deaths)
  of "streak": result = vnum(pvp.stats[i].streak)
  of "connected": result = vbool(i >= pvp.playerConnected.len or pvp.playerConnected[i])
  of "alive": result = vbool(p.hp > 0)
  of "isLocal": result = vbool(i == pvp.localPlayerIndex)
  else: found = false

proc pvpPlayerMoved(p: Player) {.nimcall.} =
  ## A script set a PvP player's x / y. On the host that is a teleport every
  ## machine snaps to; on a client it only moves the local copy.
  if modCtx.match.isNil: return
  let pvp = PvPGameState(modCtx.match)
  if not pvp.networkManager.isHost(): return
  let i = pvp.playerIndexOf(p)
  if i >= 0: pvp.modTeleport(i, p.pos)

proc pvpBulletField(b: Bullet, name: string, found: var bool): ScriptValue {.nimcall.} =
  ## A PvP bullet's owner (a player, or nil), and its mod kind and pierce.
  found = false
  result = NilValue
  if name notin PvPBulletExtras or modCtx.match.isNil: return
  let pvp = PvPGameState(modCtx.match)
  found = true
  case name
  of "owner":
    let o = b.ownerPlayerIndex
    result = if o >= 0 and o < pvp.players.len: wrapPlayer(pvp.players[o]) else: NilValue
  of "kind": result = vstr(b.modKind)
  of "pierce": result = vnum(b.modPierce.int)
  else: found = false

proc pvpBulletLive(b: Bullet): bool {.nimcall.} =
  not modCtx.match.isNil and PvPGameState(modCtx.match).pvpBulletAlive(b)

# ------------------------------------------------------------- the class ----
proc makeMatchClass() =
  matchClass = UdClass(name: "match", cached: true)
  matchClass.index = proc (vm: VM, ud: Userdata, key: ScriptValue): ScriptValue =
    let meth = rawGet(matchMethods, key)
    if meth.kind != vkNil: return meth
    let m = unwrapMatch(vud(ud))
    if m.isNil: vm.runtimeError("no PvP match in progress ('match' only exists while one is played)")
    let pvp = PvPGameState(m)
    let name = keyName(key)
    case name
    of "isHost": vbool(pvp.networkManager.isHost())
    of "mode": vstr(pvp.config.modMode)
    of "localPlayer": wrapPlayer(pvp.players[pvp.localPlayerIndex])
    of "time": vnum(pvp.gameTime.float64)
    of "timeLeft":
      if pvp.config.timeLimit <= 0: vnum(Inf)
      else: vnum(max(0.0, pvp.config.timeLimit.float64 - pvp.gameTime.float64))
    of "live": vbool(pvp.gameStarted and not pvp.isCountingDown and not pvp.gameOver)
    of "countdown": vbool(pvp.isCountingDown)
    of "over": vbool(pvp.gameOver)
    of "teams": vbool(pvp.teamsEnabled)
    of "width": vnum(pvp.screenWidth.int)
    of "height": vnum(pvp.screenHeight.int)
    of "playerCount": vnum(pvp.players.len)
    of "settings": settingsTable(pvp)
    of "data":
      let owner = vm.requireOwner("match.data")
      vtable(matchDataFor(pvp, owner))
    else:
      vm.runtimeError("match has no field '" & name & "' (" & MatchFields.join(", ") & ")")
  matchClass.newindex = proc (vm: VM, ud: Userdata, key, val: ScriptValue) =
    let m = unwrapMatch(vud(ud))
    if m.isNil: vm.runtimeError("no PvP match in progress")
    let name = keyName(key)
    if name == "data":
      # The host's copy is the one every machine gets; a client's change is
      # local until the host's next copy arrives.
      if val.kind != vkTable: vm.runtimeError("match.data must be a table")
      setMatchData(m, vm.requireOwner("match.data"), val.tbl)
    else:
      vm.runtimeError("match." & name & " cannot be set (only data can)")
  matchClass.tostr = proc (ud: Userdata): string = "match"

# ------------------------------------------------------------ methods ----
proc installMatchMethods() =
  matchMethods = newScriptTable()

  # ---- reading (every machine)
  matchMethods.reg("players") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## for p in match:players() do ... end -- everyone still connected, alive or not
    let pvp = vm.selfMatch(args, "players")
    var i = 0
    ret.setRet(vnative(newNative("players_iterator", proc (vm: VM, a: openArray[ScriptValue], r: var RetVals) =
      while i < pvp.players.len:
        let idx = i
        inc i
        if idx < pvp.playerConnected.len and not pvp.playerConnected[idx]: continue
        r.setRet(wrapPlayer(pvp.players[idx]))
        return
      r.setRet(NilValue))))
  matchMethods.reg("player") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## match:player(index) -> the player in that slot (1-based), or nil
    let pvp = vm.selfMatch(args, "player")
    let n = vm.checkInt(args, 1, "player")
    ret.setRet(if n >= 1 and n <= pvp.players.len: wrapPlayer(pvp.players[n - 1]) else: NilValue)
  matchMethods.reg("isMode") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## match:isMode(MODE) -- the key register.pvpmode returned
    let pvp = vm.selfMatch(args, "isMode")
    let want = vm.checkStr(args, 1, "isMode")
    ret.setRet(vbool(pvp.config.modMode.len > 0 and want == pvp.config.modMode))
  matchMethods.reg("nearestPlayer") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## match:nearestPlayer(x, y [, maxDist [, except]]) -> the closest living player
    let pvp = vm.selfMatch(args, "nearestPlayer")
    let x = vm.finite(arg(args, 1), "nearestPlayer's x")
    let y = vm.finite(arg(args, 2), "nearestPlayer's y")
    let maxD = if arg(args, 3).kind == vkNil: 1.0e9'f32 else: vm.finite(arg(args, 3), "nearestPlayer's maxDist")
    let skip = vm.optPlayerArg(pvp, arg(args, 4), "match:nearestPlayer's except")
    var best = -1
    var bestD = maxD * maxD
    for i, p in pvp.players:
      if i == skip or p.hp <= 0: continue
      if i < pvp.playerConnected.len and not pvp.playerConnected[i]: continue
      let dx = p.pos.x - x
      let dy = p.pos.y - y
      let d = dx * dx + dy * dy
      if d <= bestD:
        bestD = d
        best = i
    ret.setRet(if best >= 0: wrapPlayer(pvp.players[best]) else: NilValue)
  matchMethods.reg("fields") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    discard vm.selfMatch(args, "fields")
    ret.setRet(namesTable(@MatchFields))

  # ---- this machine only (presentation)
  matchMethods.reg("toast") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## match:toast(text [, color]) -- on this machine (broadcast to show it everywhere)
    let pvp = vm.selfMatch(args, "toast")
    let text = vm.localText(arg(args, 1), "match:toast's text")
    let col = if arg(args, 2).kind == vkNil: Color(r: 120, g: 220, b: 160, a: 255)
              else: parseColor(vm, arg(args, 2), "match:toast")
    pvp.modToast(text, col)
  matchMethods.reg("banner") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## match:banner(text [, sub [, color]]) -- the big callout, on this machine
    let pvp = vm.selfMatch(args, "banner")
    let text = vm.localText(arg(args, 1), "match:banner's text")
    let sub = vm.localText(arg(args, 2), "match:banner's sub")
    let col = if arg(args, 3).kind == vkNil: Color(r: 255, g: 203, b: 0, a: 255)
              else: parseColor(vm, arg(args, 3), "match:banner")
    pvp.modBanner(text, sub, col)
  matchMethods.reg("particles") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## match:particles(x, y [, color [, count = 20]]) -- a burst, on this machine
    let pvp = vm.selfMatch(args, "particles")
    let col = if arg(args, 3).kind == vkNil: Color(r: 255, g: 255, b: 255, a: 255)
              else: parseColor(vm, arg(args, 3), "match:particles")
    pvp.modParticles(vm.finite(arg(args, 1), "particles' x"), vm.finite(arg(args, 2), "particles' y"),
                     col, vm.optInt(args, 4, "particles", 20))

  # ---- messages
  matchMethods.reg("request") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## match:request(name [, data]) -- from any machine to the host's pvpRequest
    ## hook (as this machine's player). Arrives in order, never twice.
    let pvp = vm.selfMatch(args, "request")
    let (name, data) = vm.messageArgs(args, "request")
    if not pvp.modRequest(name, data):
      vm.runtimeError("match:request: too many requests are waiting for the host")
  matchMethods.reg("broadcast") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## match:broadcast(name [, data]) -- host: to every machine's pvpBroadcast
    ## hook, its own included. Arrives in order, never twice.
    let pvp = vm.hostMatch(args, "broadcast")
    let (name, data) = vm.messageArgs(args, "broadcast")
    if not pvp.modBroadcast(name, data):
      vm.runtimeError("match:broadcast: too many broadcasts are waiting (a client has stopped answering)")

  # ---- changing the match (host)
  matchMethods.reg("spawnBullet") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## match:spawnBullet{x, y, vx, vy, owner = player, damage, radius,
    ##   lifetime = 5, color = "#ff8800", kind = "rocket", pierce = 0} -> the bullet
    let pvp = vm.hostMatch(args, "spawnBullet")
    let t = vm.checkTable(args, 1, "spawnBullet")
    vm.checkKeys(t, BulletKeys, "match:spawnBullet")
    let owner = vm.optPlayerArg(pvp, rawGetStr(t, "owner"), "match:spawnBullet's owner")
    proc numOr(key: string, def: float32): float32 =
      let v = rawGetStr(t, key)
      if v.kind == vkNil: def else: vm.finite(v, "match:spawnBullet's " & key)
    let ownerP = if owner >= 0: pvp.players[owner] else: nil
    if ownerP.isNil and (rawGetStr(t, "x").kind == vkNil or rawGetStr(t, "y").kind == vkNil):
      vm.runtimeError("match:spawnBullet needs x and y (or an owner to fire from)")
    let pos = newVector2f(numOr("x", (if ownerP.isNil: 0'f32 else: ownerP.pos.x)),
                          numOr("y", (if ownerP.isNil: 0'f32 else: ownerP.pos.y)))
    let vel = newVector2f(numOr("vx", 0), numOr("vy", 0))
    let damage = max(0'f32, numOr("damage", (if ownerP.isNil: pvp.config.startDamage else: ownerP.damage)))
    let radius = max(numOr("radius", pvp.config.bulletRadius), 0.5'f32)
    let life = max(numOr("lifetime", PvPBulletLife), 0.01'f32)
    let cv = rawGetStr(t, "color")
    let color = if cv.kind == vkNil: Color(r: 0, g: 0, b: 0, a: 0)
                else: parseColor(vm, cv, "match:spawnBullet's color")
    let kv = rawGetStr(t, "kind")
    var kind = ""
    if kv.kind == vkString: kind = kv.str.s
    elif kv.kind != vkNil: vm.runtimeError("match:spawnBullet's kind must be a string")
    if kind.len > MaxModMsgName: vm.runtimeError("match:spawnBullet's kind is too long (" & $MaxModMsgName & " max)")
    let pierce = clamp(int(numOr("pierce", 0)), 0, int32.high)
    let b = pvp.modSpawnBullet(owner, pos, vel, damage, radius, life, color, kind, pierce)
    if b.isNil:
      vm.runtimeError("match:spawnBullet: the arena already holds " & $MaxPvPBullets & " bullets")
    ret.setRet(wrapBullet(b))
  matchMethods.reg("removeBullet") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## match:removeBullet(bullet) -- gone at the next step (on every machine)
    discard vm.hostMatch(args, "removeBullet")
    let b = unwrapBullet(arg(args, 1))
    if b.isNil: vm.argError("removeBullet", 1, "a bullet expected")
    b.lifetime = 0
  matchMethods.reg("damage") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## match:damage(player, amount [, attacker]) -- like a hit (FIREWALL.SYS
    ## blocks it; a kill is credited to attacker)
    let pvp = vm.hostMatch(args, "damage")
    let victim = vm.playerArg(pvp, arg(args, 1), "match:damage's player")
    let amount = max(0'f32, vm.finite(arg(args, 2), "match:damage's amount"))
    pvp.modDamage(victim, vm.optPlayerArg(pvp, arg(args, 3), "match:damage's attacker"), amount)
  matchMethods.reg("kill") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## match:kill(player [, killer])
    let pvp = vm.hostMatch(args, "kill")
    let victim = vm.playerArg(pvp, arg(args, 1), "match:kill's player")
    pvp.modKill(victim, vm.optPlayerArg(pvp, arg(args, 2), "match:kill's killer"))
  matchMethods.reg("heal") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## match:heal(player, amount) -- up to its max HP
    let pvp = vm.hostMatch(args, "heal")
    pvp.modHeal(vm.playerArg(pvp, arg(args, 1), "match:heal's player"),
                vm.finite(arg(args, 2), "match:heal's amount"))
  matchMethods.reg("teleport") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## match:teleport(player, x, y) -- every machine snaps it there
    let pvp = vm.hostMatch(args, "teleport")
    pvp.modTeleport(vm.playerArg(pvp, arg(args, 1), "match:teleport's player"),
                    newVector2f(vm.finite(arg(args, 2), "match:teleport's x"),
                                vm.finite(arg(args, 3), "match:teleport's y")))
  matchMethods.reg("finish") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## match:finish([winner [, reason]]) -- ends the match now. winner: a
    ## player, a team ("red" / "ptRed") or nil for a draw; reason: the line
    ## under the result ("Text" or {en = .., es = ..})
    let pvp = vm.hostMatch(args, "finish")
    var idx = -1
    var team = ptNone
    let w = arg(args, 1)
    if w.kind == vkString: team = vm.teamArg(w, "match:finish's winner")
    elif w.kind != vkNil: idx = vm.playerArg(pvp, w, "match:finish's winner")
    let (en, es) = vm.textPair(arg(args, 2), "match:finish's reason")
    pvp.modFinish(idx, team, if es.len > 0: en & EndTextSeparator & es else: en)

# ------------------------------------------------------- register.pvpmode ----
proc settingValue(vm: VM, s: PvPSetting, v: ScriptValue): float64 =
  ## A number, or true / false where the lobby has an on/off (packages, teams;
  ## false also switches off killLimit, timeLimit, respawn and walls).
  let what = "register.pvpmode: settings." & $s
  case v.kind
  of vkNumber:
    if not (abs(v.n) < 1.0e9): vm.runtimeError(what & " must be a finite number")
    v.n
  of vkBool:
    if v.b:
      case s
      of psPackages: 1.0
      of psTeams: 2.0
      else: vm.runtimeError(what & " must be a number (true only works for packages and teams)")
    else:
      if s notin {psPackages, psTeams, psKillLimit, psTimeLimit, psRespawn, psWalls}:
        vm.runtimeError(what & " must be a number")
      0.0
  else: vm.runtimeError(what & " must be a number or a boolean")

proc installModPvP*(base: ScriptTable) =
  ## The loader, after installModEngine.
  makeMatchClass()
  installMatchMethods()
  pvpPlayerFieldImpl = pvpPlayerField
  pvpPlayerMovedImpl = pvpPlayerMoved
  pvpBulletFieldImpl = pvpBulletField
  pvpBulletLiveImpl = pvpBulletLive
  # The match on screen (nil box), like `game` for a run
  rawSet(base, vstr("match"), vud(Userdata(cls: matchClass, box: MatchBox(m: nil), key: nil)))

  let registerT = rawGetStr(base, "register").tbl
  registerT.reg("pvpmode") do (vm: VM, args: openArray[ScriptValue], ret: var RetVals):
    ## register.pvpmode{id = "hill", name = {en = .., es = ..}, description = ..,
    ##   settings = {hp = 5, killLimit = false, timeLimit = 240, teams = false, ...},
    ##   onStart = function(match) ... end} -> the mode's key, for match:isMode
    let owner = vm.requireLoading("register.pvpmode")
    let t = vm.checkTable(args, 0, "pvpmode")
    vm.checkKeys(t, PvPModeKeys, "register.pvpmode")
    let key = mods[owner].id & ":" & vm.checkName(t, "register.pvpmode")
    if findPvPMode(key) >= 0: vm.runtimeError("register.pvpmode: '" & key & "' is already registered")
    var m = PvPModeDef(key: key, owner: owner)
    (m.nameEn, m.nameEs) = vm.textPair(rawGetStr(t, "name"), "register.pvpmode: name")
    if m.nameEn.len == 0: m.nameEn = key
    (m.descEn, m.descEs) = vm.textPair(rawGetStr(t, "description"), "register.pvpmode: description")
    let s = rawGetStr(t, "settings")
    if s.kind == vkTable:
      for (k, v) in pairsCursor(s.tbl):
        var names: seq[string]
        for x in PvPSetting: names.add($x)
        if k.kind != vkString:
          vm.runtimeError("register.pvpmode: settings keys must be names (" & names.join(", ") & ")")
        var setting: PvPSetting
        try: setting = parseEnum[PvPSetting](k.str.s)
        except ValueError:
          vm.runtimeError("register.pvpmode: unknown setting '" & k.str.s & "' (" & names.join(", ") & ")")
        m.settings.add((setting, clampPvPSetting(setting, vm.settingValue(setting, v))))
    elif s.kind != vkNil:
      vm.runtimeError("register.pvpmode: settings must be a table")
    let os = rawGetStr(t, "onStart")
    if os.kind == vkFunction: m.onStart = os
    elif os.kind != vkNil: vm.runtimeError("register.pvpmode: onStart must be a function")
    pvpModes.add(m)
    ret.setRet(vstr(key))
