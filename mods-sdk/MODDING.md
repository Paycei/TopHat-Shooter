# TopHat-ShooterOS modding guide

Mods change how the game plays: new rules, new enemies, bosses and power-ups,
new game modes, new looks. They are programs written in **Lua 5.5** (the real
thing, built into the game) with the whole standard library: files, the OS,
`require`, `load`, `debug`.

A mod can reach everything: every field of the game state (down to nested
lists and objects) and its global state (settings, statistics, the profile),
every one of the game's own procs (call them, or wrap and replace them with
mixins), raylib itself, the screens of the game (add its own) and its
languages (add new ones). On top of that it gets a friendly layer: hooks at
the moments that matter (movement, dash, shooting, bullets, pickups, the shop,
level-ups, enemy AI, boss attacks...), its own HUD, first-person 3D worlds,
PvP modes, textures, videos and 3D models, music, fonts, shaders, and apps of
its own on the desktop.

> **Mods are trusted.** A mod runs with full access to the game and to your
> files, like any program you install. Mods in MODS.EXE's **Marketplace** (the
> official registry, see [Publishing your mod](#publishing-your-mod)) are
> reviewed and approved before they are listed; install mods from anywhere
> else only if you trust who made them.

> **Modded runs count as cheated.** Any run started while at least one mod is
> loaded earns no Data Shards, statistics, advancements or unlocks. The one
> exception: a run keeps its rewards when *every* loaded mod sets
> `"disableAchievements": false` in its `mod.json` (see below), which is meant
> for mods that don't change how a run plays. Otherwise unload
> every mod (MODS.EXE, untick, Apply & Reload) to play for keeps again.

## Getting started

1. Open **MODS.EXE** on the desktop and install an example mod from the
   **Marketplace** tab: the game ships no mods, and the examples are listed
   there with the others (see [The examples](#the-examples)). **Modding Docs**,
   in the Installed tab, writes this guide and the API reference into your mods
   folder.
2. Tick the mod, press **Apply & Reload**, start a run.
3. Press **Open Folder**, copy the example's folder, rename it, change the `id`
   in its `mod.json`, and start editing. Apply & Reload picks up your changes;
   the **Log** tab shows `print` output and every error with its file and line,
   and the **Console** tab runs Lua as you type it.
4. Keep **API.md** at hand (Modding Docs writes it next to this guide): it
   lists every function, hook and proc this build has.

Mods live in `<game data>/mods/<folder>/` (the folder Open Folder shows) or,
for portable installs, in a `mods` folder next to the game executable.
Published mods are in MODS.EXE's **Marketplace** tab, and
[Publishing your mod](#publishing-your-mod) explains how to list yours there.

## mod.json

```json
{
  "id": "my_mod",
  "name": "My Mod",
  "version": "1.0.0",
  "author": "you",
  "description": "What it does, shown in MODS.EXE.",
  "main": "main.lua",
  "dependencies": ["other_mod"],
  "loadAfter": ["optional_mod"],
  "game": "6.4.0",
  "disableAchievements": true
}
```

* `id`: 1-40 characters, lowercase letters, digits and `_`. It must be unique.
* `main`: the script run when the mod loads (default `main.lua`).
* `dependencies`: mods that must be enabled and load first. If one is missing
  or fails, this mod is skipped.
* `loadAfter`: mods that load first *if* they are enabled.
* `game`: the oldest game version the mod is made for (`"6.4.0"`). On an
  older game it still loads, but MODS.EXE and the Log warn that parts of it
  may not work. In code, `engine.version` and `engine.atLeast` tell the same.
* `disableAchievements`: `true` (the default) makes every run with this mod
  loaded cheated. Set `false` only for mods that don't change how a run plays
  (cosmetics, shaders, HUD readouts, apps). A run keeps its Data Shards,
  statistics, advancements and unlocks only if *every* loaded mod says `false`;
  one mod with `true` (or without the key) makes it cheated. It must be a JSON
  boolean: `"false"` in quotes makes the manifest invalid and the mod does not
  load. Modded runs still keep their own saves either way, and
  MODS.EXE tags such mods KEEPS REWARDS.

Mods load in dependency order, ties broken by id. The order does not depend
on how you arranged anything, so two players with the same mods always load
them identically.

## The language

Mods are written in **Lua 5.5**, the official implementation, so the Lua
reference manual (www.lua.org/manual/5.5) and any tutorial apply: closures,
metatables, coroutines, string patterns (`match`, `gmatch`, `gsub`), `goto`,
integers and floats (`7 // 2` is `3`, `7 / 2` is `3.5`), bitwise operators,
`<const>` locals and so on.

Every standard library is there: `string`, `table`, `math`, `utf8`,
`coroutine`, `io`, `os`, `debug`, `package` and the base functions (`load`,
`loadfile`, `dofile`, `pcall`, `collectgarbage`, `string.dump`...). `print`
and `warn` write to the Log tab. A few things differ from a stand-alone Lua,
because this one lives inside a game:

* Relative paths mean your mod's folder: `io.open("data/notes.txt")`,
  `io.lines`, `io.input`/`io.output`, `loadfile`, `dofile`, `os.remove` and
  `os.rename` all start there. Absolute paths go anywhere. `mod.dir` is your
  folder and `mod.path("x")` the absolute path of a relative one.
* Write your own files into `mod.dataDir()`, a folder of yours in the
  player's profile. Files written into your mod folder change the mod's
  fingerprint, which moves its saved runs to a new slot (and PvP only matches
  players whose mods are identical).
* `load`, `loadfile` and `dofile` give the code they load your mod's globals
  unless you pass another environment. A chunk may be source or bytecode
  (`string.dump`, `luac` 5.5).
* No native modules: `package.loadlib` and C modules are switched off, so a
  mod runs the same on Windows, Linux and Android. `package.path` starts
  empty (see `require` below); you may add to it.
* `os.exit([code])` closes the game the normal way at the end of the frame
  (the run is saved like the window's close button saves it); your script
  stops there.
* `os.setlocale` cannot change the number format (`"numeric"` or `"all"`):
  the game reads and writes numbers in the C format. The other categories
  work.
* `debug.debug` is not available: the game has no terminal.
* `io.popen` and `os.execute` run commands in the game's working folder with
  the platform's shell, so they are the one part of a mod that behaves
  differently on each platform.
* On Windows a file opened in text mode (`"r"`, `"w"`) turns `"\n"` into
  `"\r\n"` when written and back when read. Open it with `"rb"` / `"wb"` to
  keep the exact bytes, the same on every platform.
* `os.clock()` is the processor time the game has used, not the time that has
  passed: use the `dt` your hooks get for time in play, and `os.time()` for the
  date.

A few extras: `math.clamp(x, lo, hi)`, `math.lerp(a, b, t)`, `math.sign(x)`,
`math.round(x)`, `string.split(s [, sep])`, `string.trim(s)`, and the Lua 5.1
names `unpack`, `math.pow` and `math.atan2` for older code.

`require("folder.file")` runs `folder/file.lua` (or `folder/file/init.lua`)
from your mod folder once and returns what it returned; `require("lib/x.lua")`
takes a path instead. `require("other_id:folder.file")` loads a module of
another loaded mod, in that mod's globals (list it in `dependencies` so it
loads first). Every module loads once and is kept in
`package.loaded["<mod id>:<module>"]`, so two mods requiring the same module
share it. Any other name goes on to Lua's own `require` (`package.preload`,
`package.path`).

Each mod has its own globals: two mods can both define `update` or change
`math` without touching each other. What every mod shares sits one level
down, in `getmetatable(_ENV).__index`: change something there and every mod
sees it.

Lua 5.5 prints whole floats with a decimal point (`10 / 2` is `5.0`); use
`//`, `math.floor` or `math.round` for whole numbers, or `%d` in
`string.format`.

### The watchdog

Mods are trusted, so nothing limits their memory, their speed or how much
they spawn, and nothing switches a mod off for erroring. One guard is left,
so that a bug cannot hang the game:

* A script call that does not return within 5 seconds (30 seconds for a
  mod's main chunk while it loads, and 10 seconds for all of one frame's
  calls together) is stopped with an error naming the line it was on.
  `pcall`, `xpcall` and coroutines cannot keep it running. Long work belongs
  in a coroutine you resume a little every frame.
* `debug.sethook` with a hook of your own takes the watchdog off that
  coroutine; `debug.sethook()` with no hook takes it off until your next call.
* The watchdog cannot stop C code that never returns: a pathological string
  pattern, a blocking `io.read`, or a command run by `os.execute`.
* Errors go to the Log tab (a repeated error is folded into a count) and the
  game carries on. MODS.EXE shows how many milliseconds each mod's scripts
  take per frame.
* If the game goes down while mods are loaded, the next launch starts with
  every mod off and says so; Apply & Reload in MODS.EXE turns them back on.
* `help licenses` in the Help terminal shows Lua's license.

## Hooks

Register functions with `hooks.on(name, fn)`; `hooks.off(name, fn)` removes
one and `hooks.list()` returns every name. Three kinds:

* **events** just tell you something happened;
* **filters** pass a value first; return a number (or value) to replace it;
* **cancels** let you return `true` to stop the game's own behaviour.

| Hook | Arguments | Kind |
|---|---|---|
| `runStart` | game, resumed | event: a run begins (or is resumed) |
| `runEnd` | game, died | event |
| `checkpoint` | game | cancel: true skips the restore point the base mode is about to save (see [Restore points](#restore-points)) |
| `restorePointUsed` | game, used, max | event: a Continue spent a restore point; fires on the continued run's first frame, after `runStart` |
| `update` | game, dt | event, every frame of play (dt in seconds), after the game's own update |
| `preUpdate` | game, dt | event, every frame of play, before the game's own update |
| `stateChange` | game, from, to | event: the run moved between screens (`"gsPlaying"`, `"gsPaused"`, `"gsShop"`, `"gsPowerUpSelect"`, `"gsGameOver"`, ...) |
| `drawBackground` | game | draw in arena coordinates, under everything else |
| `drawWorld` | game | draw in arena coordinates (like `player.x`), over the world |
| `drawHud` | game, w, h | draw in screen coordinates |
| `drawDesktop` | w, h | draw on the desktop, over the wallpaper and under the windows |
| `waveStart` / `waveEnd` | game, wave | events (wave and roguelite rooms) |
| `waveEnemyCount` | count, game, wave | filter: how many enemies the wave has |
| `waveSpawn` | type, game, wave | filter: return another enemy type name |
| `spawnInterval` | seconds, game | filter: time between spawn bursts |
| `bossForWave` | bossId, game, wave | filter: which boss fights here (any id, yours too) |
| `survivalSpawn` | type, game | filter: the survival horde's next enemy |
| `survivalEvent` | game, eventName | cancel: return true to skip a System Event |
| `floorStart` / `roomEnter` / `roomCleared` | game, number | events (roguelite) |
| `rogueSpawn` | type, game | filter: a roguelite room's next enemy |
| `enemySpawn` | enemy | event, as each regular enemy is created |
| `enemyUpdate` | enemy, dt | cancel: true skips the built-in AI this frame |
| `enemyDraw` | enemy | cancel: true skips the built-in body (draw your own) |
| `enemyDamaged` | amount, enemy | filter: damage an enemy is about to take (all sources) |
| `enemyDeath` | enemy, game | event (bosses too) |
| `bossSpawn` / `bossDeath` | boss, game | events |
| `bossPhase` | boss, phaseIndex | event |
| `bossAttack` | boss, attack | cancel: true stops that attack |
| `shoot` | player, game, dirX, dirY | cancel: true replaces the player's shot |
| `bulletSpawn` | bullet | event, as any bullet (player or enemy) is created: change it before it flies |
| `bulletUpdate` | bullet, dt | cancel: true skips the built-in movement (its lifetime still runs out) |
| `bulletDraw` | bullet | cancel: true skips the built-in look |
| `bulletHit` | damage, bullet, enemy | filter: a player bullet's damage on hit |
| `bulletExpire` | bullet | event: a bullet's lifetime ran out (it missed) |
| `thingSpawn` / `thingDeath` | thing | events: a thing joined the arena / its HP ran out (see [Things](#things-hazards-and-projectiles)) |
| `statusApplied` | target, name, stacks | event: a status (see [Statuses](#statuses)) was applied to an enemy or the player |
| `statusExpired` | target, name, expired | event: a status went away (`expired`: it ran out rather than being cleared) |
| `enemyContact` | damage, enemy, player | filter: the damage of an enemy's (or a boss's) touch |
| `bulletHitPlayer` | damage, bullet, player | filter: an enemy bullet landing on the player |
| `cacheOpen` | tier, game, x, y | cancel: true takes a survival Data Cache without its rewards (`tier`: `"sctMinor"` ... `"sctKernel"`) |
| `abilityUsed` | game | event: the player pressed [Q] (after the built-in abilities ran) |
| `patchInstalled` | name, game | event: a roguelite patch was installed (`"rrtOverclock"`, or a mod patch's name) |
| `playerDamaged` | amount, player | filter: damage the player is about to take |
| `playerLethal` | player | cancel: true keeps the player alive (set `player.hp` yourself) |
| `playerHeal` | amount, player | filter |
| `playerDraw` | player | cancel: true skips the built-in body |
| `playerUpdate` | player, dt | cancel: true skips the built-in movement (move the player yourself) |
| `dash` | player | cancel: true stops the dash (do your own: see `house_rules`) |
| `placeWall` | x, y, game | cancel: true places no wall |
| `ability` | game | cancel: true skips the built-in [Q] abilities |
| `combatStats` | player, stats | edit `stats.damage`, `fireRate`, `critChance`, `critMultiplier` |
| `powerUpChoices` | names, player | filter: return a list of power-up names to offer |
| `powerUpPicked` | name, level, game | event |
| `powerUpApply` | name, level, player | cancel: true skips the power-up's pickup stat changes |
| `levelUp` | game, level | event, per level gained |
| `xpToLevel` | xp, level, mode | filter: XP needed to clear `level` |
| `coinValue` / `xpValue` | amount, enemy | filter: what a kill pays |
| `pickup` | kind, value, game | cancel: true takes the pickup without its built-in effect (`kind`: `"coin"`, `"xp"` or a consumable such as `"ctHealth"`; boss coins always count) |
| `shopBuy` | index, name, cost, game | cancel: true refuses (or replaces) a shop purchase |
| `world3dStart` | world, resumed | event: a 3D world's first frame (see [3D worlds](#3d-worlds)) |
| `world3dPreUpdate` / `world3dUpdate` | world, dt | events, every frame of a world, before / after its simulation |
| `world3dEnd` | world, result | event: the world ended (`"won"`, `"lost"` or `"exit"`) |
| `world3dDraw` | world | draw in the 3D view with `draw3d` |
| `world3dDrawHud` | world, w, h | draw in screen coordinates over a 3D world |
| `world3dShoot` | world | cancel: true replaces the player's shot |
| `world3dHit` | damage, target, projectile | filter: a player shot's damage on an entity, `"boss"` or `"satellite"` |
| `world3dPlayerDamaged` | amount, source, entity | filter: damage the 3D player is about to take |
| `world3dPlayerLethal` | | cancel: true keeps the 3D player alive (set `health` yourself) |
| `world3dEntitySpawn` / `world3dEntityDeath` | entity | events: an entity joined / died |
| `world3dEntityUpdate` | entity, dt | cancel: true skips the entity's built-in AI this frame |
| `world3dEntityDraw` | entity | cancel: true skips the entity's built-in body |
| `world3dBossPhase` | phase | event: the 3D boss changed phase |
| `world3dBossAttack` | phase, pattern | cancel: true stops that attack |
| `world3dPickup` | pickup | cancel: true takes the pickup without its built-in effect |
| `pvpStart`, `pvpEnd`, `pvpUpdate`, `pvpShoot`, ... | match, ... | the PvP hooks: see [PvP](#pvp), which has their table |
| `frame` | state, dt | event, the top of every frame in every state (the desktop and menus too; `state` is a GameState name such as `"gsMenu"`), a safe point. No run objects: see [Screens and the frame](#screens-and-the-frame) |
| `screenUpdate` | state, dt | cancel: true takes this frame over (the state's own update and drawing are skipped; `screenDraw` paints it) |
| `screenDraw` | state, w, h | draw the frame a `screenUpdate` took, in screen coordinates |
| `drawOverlay` | state, w, h | draw over everything, in every state, every frame (screen coordinates) |

Enemy types are named like the game's own (`"etCircle"`, `"etCube"`,
`"etThread"`, `"etFragment"`...); `enemies.types()` lists them all.

### Mod events

Mods can talk to each other through events of their own. A hook name with a
colon, `"<mod id>:<event>"`, is a mod event: `hooks.on` and `hooks.off` take
it like any hook, and

* `hooks.emit(name, ...)` calls every handler of `name`, in the order they
  were added;
* `hooks.filter(name, value, ...)` passes `value` through every handler (each
  gets `(value, ...)` and may return a replacement) and returns the result.

```lua
-- necromancer/main.lua
hooks.emit("necromancer:raised", ally, enemy)
local souls = hooks.filter("necromancer:soulValue", 1, enemy)

-- another mod
hooks.on("necromancer:raised", function(ally, enemy) ally.data.glow = true end)
hooks.on("necromancer:soulValue", function(n, enemy) return n * 2 end)
```

Name your events after your own mod id. An event that raises itself more than
16 levels deep stops with an error, and the handlers of a mod that is switched
off go with it.

## The game, the player, enemies and bullets

`game` and `player` are always available during a run (they are also passed
to most hooks). Enemies and bullets come from hooks and iterators.

**Every field can be read by name and written**, all the way down: numbers,
flags, text and enums, but also nested objects, lists and tables.

```lua
player.damage = player.damage * 1.5
e.speed = 0
game.survival.xpMult = 2                 -- a nested object
game.shopItems[1].baseCost = 5           -- a list (1-based) of objects
for i, pu in ipairs(player.powerUps) do print(pu.powerType, pu.level) end
print(#game.coins, #game.walls, game.dopamine.comboSystem)
for name, value in pairs(game.bossWaveManager) do print(name, value) end
```

* Enum fields read and write as names (`e.enemyType == "etCube"`); sets of
  enums as lists of names. Call `obj:fields()` on anything for its fields.
* Positions have shortcuts: `x`, `y` (position) and `vx`, `vy` (velocity).
* Vector and colour fields come back as copies (`{x = .., y = ..}`,
  `{r, g, b, a}`). Change them by assigning the whole value:
  `e.pos = {x = 100, y = 200}`. A nested object can also be assigned from a
  table of its fields (or from another object of its kind, which copies it),
  and a list from a list.
* Object fields can point somewhere else: `e.target = otherEnemy`, or `nil`
  where the game allows one.
* Nested objects and list entries are live views, not copies: keep one in a
  variable and it follows the game. If what it pointed at is gone (a list
  shrank), using it is an error that says so. `x:copy()` gives a plain table
  of its data that survives it.
* Lists grow and shrink: `list:add(v)`, `list:insert([pos,] v)`,
  `list:remove([pos])`, `list:clear()`, `list:resize(n)`. A new item can be a
  table of its fields, another object of its kind, or (in an entity list) an
  entity. Tables (fields keyed by names, enums or numbers) read and write by
  key; a new key adds an entry and `nil` removes one.
* Changing how many items a list or table holds only works at a **safe
  point**, where the game is not walking its lists: while your mod loads, in
  a timer, in the `preUpdate`, `update`, `runStart`, `frame` and
  `screenUpdate` hooks, in an app or a screen (`ui.open`'s and
  `register.screen`'s), in the Console, and in an `engine.defer` function.
  Anywhere else (a hook the game
  fires from inside one of its loops) the change is refused with an error;
  wrap it in `engine.defer(function() ... end)`, which runs it at the next
  safe point (after the frame's simulation, or at the top of the next frame).
* Setting an enemy's `hp` sets it outright (it is not damage: no hooks, no
  stats); a boss's is its current phase pool, and an empty pool moves the
  boss to its next phase, or defeats it, the normal way. `maxHp`, `type`,
  `bossDefinitionID` and `currentPhaseIndex` (a real phase change) are
  writable too, and so is `game.state`, which changes at the next safe point.
* A few fields stay read-only because the game keys on them: an enemy's `id`
  and `isBoss`; the run's `mode`, its save slot, the screen size, and the
  reward rule's `modded` / `cheatsUsed` / `modFingerprint`.
* **Your real progression is writable** (`game.rogueliteProfile` and
  everything in `engine.globals`, below), so a mod can build its own
  meta-progression or unlock things. The reward rule still holds: a run with
  a mod that disables achievements earns nothing on its own.
* Writing nonsense (a negative size, an index past a list's end in a field the
  game uses as one) can break the run or crash the game: the game trusts its
  own numbers.

Methods:

* `game.enemies` and `game.bullets` are the live lists (`#game.enemies`,
  `game.enemies[1]`); calling one iterates it, skipping dead enemies:
  `for e in game:enemies() do`.
* `game:enemyCount()`, `game:nearestEnemy(x, y [, maxDist])`,
  `game:enemiesNear(x, y, radius)`, `game:isMode("wave")` (also `"survival"`,
  `"roguelite"`, `"sandbox"` or a mod game mode id).
* `player:powerUpLevel("puDoubleShot")`, `player:hasPowerUp(name)`.
* `enemy:valid()`: still alive and still in the run; `bullet:valid()`: still
  flying.
* `enemy:kill()` (with rewards; a boss skips its remaining phases),
  `enemy:remove()` (no death, no rewards; a boss is never removed, since its
  boss wave only ends through its defeat: `enemy:kill()` defeats it at once),
  `enemy:heal(n)`.

### The game's global state

`engine.globals` reaches everything outside the run, read and written like
`game`: `settings` (the player's settings), `stats` (lifetime statistics),
`roguelite` (the roguelite profile), `advancements`, `runStats` (the run's
statistics), `sound` (the sound system), `difficulty`, `language`,
`profileSlot`, `game` (the run on screen, if any), `world3d`, `desktop` (the
desktop and its icons) and `windows` (every window of the OS: the shop,
settings, stats...). `for name in pairs(engine.globals) do print(name) end`
lists them.

```lua
engine.globals.settings.screenShakeScale = 0
engine.globals.roguelite.dataShards = engine.globals.roguelite.dataShards + 100
```

Changes are saved when the game saves that state (settings when you leave
Settings or close the game, the profile at the end of a run...).

The profile's progression loads after the mods do, so that its saves can
name your mod's content: while your main chunk runs (at startup, and again
when the player switches profile), `stats`, `roguelite`, `advancements` and
`runStats` hold nothing yet at startup and the previous profile's data after
a switch, and what you change in them is lost. Read and change them from a
hook (`frame`, `runStart`...), which only runs once the profile is loaded.

### Your own data on an entity

`e.data` (and `b.data` on a bullet) is a table of your own for that one enemy
or bullet: put anything in it.

```lua
hooks.on("enemySpawn", function(e) e.data.hits = 0 end)
hooks.on("bulletHit", function(dmg, b, e)
  e.data.hits = (e.data.hits or 0) + 1
  if e.data.hits >= 5 then return dmg * 3 end
end)
```

* Each mod sees its own table: two mods' `e.data.hits` never collide.
* It lives as long as the entity does (it is forgotten a moment after the
  enemy dies or the bullet is gone).
* Plain data (numbers, strings, booleans, tables) comes back when a suspended
  run is resumed exactly (quitting to the desktop). A run restarted from a run
  save or a restore point rebuilds its enemies, so their data starts empty:
  keep what must survive that in `run.data`.

## Mixins: changing the game's own code

Hooks fire at the moments the game offers them. **Mixins** go further: they
wrap the game's own procs, the functions its code is made of, so a mod can
change what any of them does, with or without the original.

```lua
-- every hit an enemy takes is doubled
mixin.wrap("combat.applyEnemyHpDamage", function(orig, enemy, damage)
  return orig(enemy, damage * 2)
end)

-- the power-up offer: change the three choices the game rolled
mixin.after("powerup.generatePowerUpChoices", function(choices, player, legendary, families, mode)
  choices[1].powerType = "puDoubleShot"
  return choices
end)

-- replace a boss's whole mechanics step
mixin.replace("bosses.updateBossMechanics", function(game, boss, dt)
  boss.speed = 50
end)
```

* `mixin.wrap(name, fn(orig, ...) [, {priority = n}])`: `fn` gets the call's
  arguments, plus `orig`, the rest of the chain (the next mod's wrap, or the
  game's original). Call `orig` with the arguments you want (the same, or
  changed), as many times as you like, or not at all; what `fn` returns is
  the result. It returns a handle for `mixin.remove(handle)`.
* `mixin.before(name, fn(...))`: runs first; returning anything but `nil`
  cancels the call, and that value is the result.
  `mixin.after(name, fn(result, ...))`: runs after the original; a non-`nil`
  return replaces the result. `mixin.replace(name, fn(...))`: the original
  never runs.
* Several mods can wrap the same proc: the highest `priority` runs outermost,
  then load order. A wrap can be added and removed at any time (from a hook,
  a timer, an app).
* Names are `<module>.<proc>`: `mixin.list([prefix])` lists every one the
  game has, `mixin.signature(name)` shows its parameters and result, and
  `mixin.has(name)` tells whether one exists. An overloaded proc (two procs
  sharing a name) is named with its parameter types:
  `"localization.t(string)"`.
* **Arguments.** Numbers, text, booleans and enum names are themselves;
  entities are the usual wrappers; other objects are proxies like `game.*`.
  An object passed by value is borrowed for the call: change it and the
  original sees the change, but it reads "no longer exists" after the call
  (`:copy()` it to keep it). A `var` parameter is the caller's own variable:
  writing it, or passing `orig` a table for it, changes what the caller has.
  Objects the game keeps by reference stay valid after the call.
* **Results** come back the same way: return what `orig` returned (edited or
  not), a table of fields for an object, or a value of your own.
* **Errors.** A wrap that errors is logged and the call goes on without it;
  the original never runs twice because of it. If the game's own code raises
  an error inside the chain and no wrap handles it (`pcall(orig, ...)`), the
  game gets the error as if no mod were there.
* A wrapped proc costs a little more than a hook on every call; wrap procs
  that run thousands of times a frame (an enemy's update, the damage door)
  with care, and watch MODS.EXE's ms/frame.
* Wraps run wherever the game calls the proc: in a run, on the desktop, in
  PvP (on every machine: the host's game decides what counts).

## The engine

`engine.<module>.<proc>(...)` calls any of those procs (the game's public
version, so other mods' wraps apply); `engine.call("module.proc", ...)` is the
same by name. Arguments a proc has defaults for may be left out. A proc only
its own module calls is *wrap only* in API.md: mixins can wrap it, scripts
cannot call it.

```lua
engine.game.startWave(game)
local stats = engine.combat.calculateCombatStats(player)
print(engine.types.difficultyEnemyHpMult())
```

`engine.globals` is the game's global state (see
[The game's global state](#the-games-global-state)), and `engine.defer(fn)`
runs `fn` at the next safe point.

## raylib

`rl` is raylib itself, the library the game draws, plays sound and reads input
with, and `rl.gl` is rlgl, the layer under it. Every function is there by its
Nim name (`rl.drawCircle`, `rl.loadTexture`, `rl.isKeyPressed`,
`rl.gl.pushMatrix`...); API.md lists them all with their parameters.

```lua
hooks.on("drawHud", function(game, w, h)
  rl.drawCircleLines(w // 2, h // 2, 40, rl.Gold)
  rl.drawFPS(10, 10)
end)
```

* Vectors, rectangles, colours and cameras are tables (`{x = 1, y = 2}`,
  `{x = .., y = .., width = .., height = ..}`, `{r = .., g = .., b = .., a = ..}`);
  `rl.Red`, `rl.RayWhite` and the rest are raylib's colours. Enums are their
  names: `rl.isKeyPressed("F7")`, `rl.beginBlendMode("Additive")`. Overloads
  (several functions sharing a name) are tried in order.
* An `out` parameter comes back after the result:
  `local hit, point = rl.checkCollisionLines(a, b, c, d)`.
* Textures, fonts, sounds, music, models, shaders, render textures... are
  **handles**. One your mod loads (`rl.loadTexture(mod.path("art/ship.png"))`)
  is yours: it is unloaded once nothing holds it, after the frame being drawn,
  and `rl.unload(handle)` unloads it now. One the game or raylib keeps
  (`rl.getFontDefault()`, a render texture's `.texture`) is a view and is never
  unloaded by you.
* Draw from the draw hooks, a screen's `draw`, an app or a `ui.open` screen:
  they run while the game draws its frame, in virtual screen coordinates
  (1024 x 768, wider in widescreen). Draw into a render texture of your own
  **outside** the game's drawing, in the `frame` hook at the top of the frame:
  `rl.beginTextureMode` inside the game's drawing would end the game's own
  texture mode. The `mixins` example draws its minimap that way.
* Left out on purpose: opening and closing the window and the audio device,
  starting and ending the frame (the game does those) and the callback setters.
  `os.exit` closes the game.
* raylib trusts what it gets: a wrong size, an unloaded handle or a draw outside
  a frame can crash the game.

## Screens and the frame

**A screen of your own** is a state of the game, like the desktop, a run or
the game-over screen:

```lua
register.screen{
  id = "map",                            -- registered as "<your id>:map"
  enter = function(from, ...) end,       -- opened (from: the state or screen it came from)
  update = function(dt) end,             -- every frame it shows (a safe point)
  draw = function(w, h) end,             -- every frame, in screen coordinates
  leave = function(to) end,              -- left (to: where it went)
  back = function() return true end,     -- Esc / gamepad B: true keeps it open
  cursor = true,                         -- the game's pointer over it (the default)
}
screens.go("map", ...)   -- opens at the top of the next frame; ... goes to enter
```

* `screens.back()` returns to the screen below, or to the game's state under
  them all; `screens.closeAll()` goes straight there. Without a `back`
  function, Esc goes back. `enter` runs when `screens.go` opens a screen, not
  when `screens.back` returns to it.
* Opened over a run, the run holds still underneath and stays the run on
  screen: `game`, `run.data` and the run's hooks keep working (the simulation
  does not run), and closing the game there saves the run as it was. Opened
  from the desktop, it comes back to the desktop.
* `screens.current()` is the id showing (or `nil`), `screens.depth()` how many
  are open and `screens.list()` every registered screen. Another mod's screen
  opens by its full id.
* If the game moves on by itself (a game over, a script setting `game.state`),
  the screens are left and each `leave` runs. Screens cannot open during a PvP
  match: the match would stop.

**The frame itself.** Four hooks run in every state, the desktop and the menus
included: `frame(state, dt)` at the top of every frame (a safe point);
`screenUpdate(state, dt)`, which takes the frame over when a handler returns
true (the state's own update and drawing are skipped, and
`screenDraw(state, w, h)` paints the frame instead); and
`drawOverlay(state, w, h)`, drawn over everything. They get no run objects:
reach the game through `engine.globals` (`engine.globals.game` is the run on
screen). With mixins on the game's own update and draw procs
(`game.updateGame`, `game.drawGame`...), nothing on screen is out of reach.

## Languages

A mod can add a language to the game:

```lua
register.language{
  id = "fr",                  -- the language's id: letters, digits, _ and -
  name = "Français",          -- what the language pickers show
  base = "en",                -- its gaps show this built-in language ("en" or "es")
  strings = assets.json("fr.json"),   -- the game's text keys -> your text
}
```

* `strings_en.json`, next to this guide in the mods folder, lists every text
  key of the game with its English: copy it, translate the values and load the
  copy as above. A key you leave out shows the base language.
  `lang.text(key)` shows a key's text in the language in use.
* Your mod's own texts take the language too: write
  `{en = "Souls", es = "Almas", fr = "Âmes"}` wherever a text is asked for
  (names, descriptions, titles, toasts).
* `lang.set("fr", key, text)` and `lang.add{fr = {key = text}}` add strings to
  a language, yours or another mod's: a translation pack is a mod that only
  adds strings (list the language's mod in `loadAfter`), or that registers the
  language itself. Registering an id again adds to it.
* The language shows in Settings (the language button cycles through every
  language) and on the first-run language screen. The player's choice is kept
  by id: while its mod is not loaded, the game shows English.
* `lang.current()` is `"en"`, `"es"` or the id in use, `lang.list()` every
  language (`{id = .., name = ..}`), and `lang.use(id)` switches to one (and
  makes it the player's choice, saved with their settings).
* The game's font has the Latin-1 letters only (U+0020 to U+00FF): accents,
  ñ, ç, ß and the like work; another script needs a font of your own
  (`assets.font`) drawn by your own code.

## The console

MODS.EXE's **Console** tab runs Lua as you type it, with the whole API: try a
call before putting it in a mod, read the game's state, or fix something by
hand.

* Enter runs the line; Up and Down go through what you typed before.
* An expression shows its value (`= 3`); a statement just runs. Globals you
  define stay for the next line. Output and errors go to the log above it
  (the Log tab shows them too).
* It sees what every mod sees: `engine.globals.game.player.hp = 99`,
  `mixin.signature("combat.damageEnemy")`, `mods.get("necromancer")`.
* It runs at a safe point and belongs to no mod: what is a mod's own
  (`register.*`, `mod.*`, a mod's `run.data`) works only in mod code.

## Versions and the API reference

* `engine.version` is the game's version (`"6.4.0"`) and
  `engine.atLeast("6.4")` tells whether this game is that version or newer.
  `engine.has("screens.go")` tells whether the API has something (a dotted
  path), and `mixin.has(name)` whether the game has a proc.
* `"game"` in mod.json names the oldest game version your mod is made for (see
  [mod.json](#modjson)).
* **API.md**, next to this guide in the mods folder (Modding Docs writes
  it), lists everything this build has: every library function with what it
  does, every hook, every one of the game's procs with its parameters (and
  whether it is moddable), raylib and `engine.globals`. It is generated from
  the game itself, so it is always complete.
* **tophat.d.lua** is the same for your editor: open the mods folder in an
  editor with the Lua language server (the "Lua" extension of VS Code, for
  one) and you get completion and signatures for the whole API, hook names and
  moddable proc names included.

## Changing the game

**Spawning.** `spawn.enemy(type, x, y [, {elite = true, difficulty = 3,
onSpawn = fn}])`, `spawn.boss(id [, {x = .., y = .., onSpawn = fn}])` and
`spawn.bullet{x, y, vx, vy, damage, radius, lifetime, fromPlayer, color}`.
Hooks run in the middle of the game's own loops, so spawns join the run at
the end of the current frame. `spawn.enemy` and `spawn.bullet` return the new
enemy or bullet right away: set it up, keep it, give it `data`; `valid()` is
already true. `onSpawn` (and `spawn.boss`'s) runs when it joins.

**Enemies.** `e:damage(amount [, source])` (bosses too: it drains the current
phase), `e:kill()` (dies with its normal rewards; a boss skips its remaining
phases), `e:remove()` (vanishes, no rewards), `e:heal(amount)`. The player has
`player:heal(amount [, source])` and `player:hurt(amount)`. `source` is a
power-up name: the damage or healing is credited to it in the run statistics
(inside a power-up's own `update`, `onHit` or `onPickup` that happens by
itself).

**Running the run.** Like spawns, these happen at the end of the frame:

* `game:startWave()`, `game:endWave()` (nothing more spawns and the regular
  enemies go, so the wave ends normally), `game:win()` (the victory screen),
  `game:lose()` (the player dies, through the normal death screens),
  `game:powerUpDraft([count])` (level-up style drafts, opened as soon as one
  may be).
* `player:give(name [, level])` installs a power-up (one level up, or up to
  `level`) with its normal effects; `player:take(name)` removes one.
* `spawn.coin(x, y [, value])`, `spawn.xp(x, y [, value])`,
  `spawn.consumable("ctHealth", x, y)`; `bullet:remove()`.

**Effects.** `fx.shake("small" | "medium" | "large" | "massive")`,
`fx.particles(x, y, color [, count])`, `fx.damageNumber(x, y, amount [, critical])`,
`fx.sound("explosion" [, volume, pitch])` with the game's sounds (`shoot`,
`enemyHit`, `enemyDeath`, `playerHit`, `coinPickup`, `powerUp`, `bossSpawn`,
`explosion`, `teleport`, ...).

**Overrides** (usually at load time):

* `override.enemy(type, fields)` changes a built-in enemy's stats. The fields
  follow the shape `enemies.config(type)` returns, for example
  `override.enemy("etCircle", {baseHP = 3, baseColor = "#40ff80",
  movement = {baseSpeed = 160}, attack = {fireRate = 0.5}})`.
  A field name that does not exist is an error, so typos never pass silently.
  Add `update = function(e, dt, game) ... end` (return true to skip the
  built-in AI) and/or `draw = function(e) ... end` to rewrite how every enemy
  of that type behaves and looks.
* `override.boss(id, fields)` replaces parts of a boss (same fields as
  `register.boss`); `bosses.get(id)` returns a copy of a definition to start from.
* `override.text(lang, key, text)`: same as `lang.set`.

**Your own bosses.** `register.boss{...}` returns the new boss's id (1000 and
up). Put it in a fight with `bossForWave` or `spawn.boss`.

```lua
local id = register.boss{
  name = "OVERCLOCK", process = "overclock.sys",
  hp = 600, speed = 60, damage = 2, radius = 42, color = "#ff5050",
  slotWave = 25,               -- the wave its numbers are written for
  weakPoint = {kind = "bwoNone"},
  phases = {
    {name = "SPIN UP", behavior = "circle_player", attacks = {
      {type = "bapSpiral", damage = 1, cooldown = 2.5, projectileSpeed = 180, projectileCount = 12},
      {type = "mod:burstRing", cooldown = 3, damage = 2, projectileCount = 10},
    }},
    {name = "MELTDOWN", hpThreshold = 0.5, speedMultiplier = 1.4, behavior = "mod:jitter",
     attacks = {{type = "bapBarrage", damage = 2, cooldown = 1.4}}},
  },
  attacks = {   -- "mod:<name>" attacks
    burstRing = function(boss, attack, game)
      for i = 1, attack.projectileCount do
        local a = i / attack.projectileCount * math.pi * 2
        spawn.bullet{x = boss.x, y = boss.y, vx = math.cos(a) * 170, vy = math.sin(a) * 170,
                     damage = attack.damage}
      end
    end,
  },
  behaviors = { -- "mod:<name>" movement, every frame: move the boss yourself
    jitter = function(boss, dt, game)
      boss.x = boss.x + math.random(-80, 80) * dt
      boss.y = boss.y + math.random(-80, 80) * dt
    end,
  },
  draw = function(boss) draw.poly(boss.x, boss.y, 6, boss.radius, game.time * 90, "#ff5050") end,
}
```

Attack `type` is one of the built-in patterns (`bapSpiral`, `bapBurst`,
`bapWave`, `bapTargeted`, `bapCircle`, `bapLaser`, `bapOrbit`, `bapMeteor`,
`bapChain`, `bapPulse`, `bapTeleport`, `bapSummon`, `bapDash`, `bapBarrage`,
`bapSnipe`, `bapMinionVolley`) with fields `damage`, `cooldown`,
`projectileSpeed`, `projectileCount`, `spreadAngle`, `durationOrRadius`,
`bulletRadius`, and optionally `special` for one of the game's own special
attacks; or `"mod:<name>"` for one of yours. Phase `behavior` is a built-in
movement (`circle_player`, `anchored`, `aggressive`, `defensive`, ...) or
`"mod:<name>"`; a `"mod:"` behaviour moves the boss by setting `boss.x` /
`boss.y` (like the built-in ones do). Without `weakPoint` a boss takes full
damage everywhere.

## Things, hazards and projectiles

A **thing** is a new kind of object in the arena, one you design: an ally, a
turret, an orbiting shield, an aura, a wall, a zone, a prop, a pickup. Register
its kind while your mod loads, then spawn as many as you like during a run.

```lua
local TURRET = register.thing{
  id = "turret", team = "player", motion = "static",
  shape = "circle", radius = 14, color = "#60e0ff", hp = 12,
  solid = true, hitByBullets = true,            -- enemies' shots wear it down
  lifetime = 20,                                -- seconds (0 = forever)
  weapon = {interval = 0.6, range = 320, damage = 1, speed = 380},
  onDeath = function(t, game) fx.particles(t.x, t.y, "#60e0ff", 30) end,
}
hooks.on("placeWall", function(x, y, game)
  spawn.thing(TURRET, x, y)
  return true                                   -- no wall: a turret instead
end)
```

`register.thing{...}` returns the kind's name (`"<your mod id>:<id>"`). Every
field is optional except `id`, and an unknown field is an error:

| Field | Meaning |
|---|---|
| `team` | `"player"` (an ally: hurts enemies, the enemies' shots hit it), `"enemy"` (hurts the player) or `"neutral"` (both) |
| `shape`, `radius`, `w`, `h` | `"circle"` (radius) or `"rect"` (w x h, centred) |
| `motion`, `speed` | `"static"`, `"free"` (flies on its `vx`/`vy`, with `friction` and `bounce` off the arena edges), `"followPlayer"` (keeps `orbitRadius` away), `"orbitPlayer"` (`speed` degrees per second at `orbitRadius`, from `orbitAngle`), `"chasePlayer"`, `"chaseEnemy"` (the nearest) |
| `angle`, `spin` | degrees, degrees per second |
| `hp` | 0 = cannot be hurt; `invulnerable = true` also ignores damage; `hpBar = false` hides its bar |
| `contactDamage`, `contactInterval` | damage to what it touches on the other side, every `contactInterval` seconds (0.5) |
| `solid` | pushes the player and regular enemies out of it |
| `blocksBullets`, `hitByBullets` | stops the other side's bullets / takes their damage (a neutral thing: everyone's) |
| `pickup`, `magnet` | taken when the player touches it (`onPickup`), and pulled toward a nearby player |
| `persistent` | in the roguelite, follows the player into the next room (others are left behind) |
| `lifetime`, `layer`, `color`, `scale`, `tag` | seconds alive (0 = forever), `"below"` / `"normal"` / `"above"` the actors, look, and a label you can search by |
| `texture`, `model`, `look` | its look (`look` takes `scale`, `rotate` and `override.model`'s pose options) instead of the plain shape |
| `weapon` | a turret: `{interval, range, speed, damage, count, spread, radius, lifetime, color, kind}`; it aims at the nearest target of the other side |
| `update`, `updateEvery` | `fn(thing, dt, game)`, every frame or every `updateEvery` seconds |
| `draw` | `fn(thing)` draws it yourself (world coordinates) |
| `onSpawn(thing, game)`, `onDeath(thing, game)`, `onExpire(thing, game)` | it joined / its HP ran out / its lifetime ran out |
| `onTouchPlayer(thing, player, game)`, `onTouchEnemy(thing, enemy, game)` | on contact (every `contactInterval`) |
| `onHit(thing, bullet, damage)` | a bullet hit it: return the damage to take |
| `onDamaged(thing, amount, source)` | any damage (`source`: `"bullet"`, `"explosion"`, `"script"`): return the amount |
| `onPickup(thing, player, game)` | it was picked up; return `false` to leave it there |

`spawn.thing(kind, x, y [, overrides])` returns the thing at once (it joins
the arena at the end of the frame). The overrides take the instance fields of
the table above (not the callbacks), `vx`/`vy`, `maxHp` and an `onSpawn`
function. A run holds up to 4000 things.

A thing works like an enemy in scripts: `t.x`, `t.y`, `t.vx`, `t.vy`, every
field by name (`t.hp`, `t.speed`, `t.orbitRadius`...), the flags as booleans
(`t.solid = false`), `t.data` (your own table, as on enemies), and
`t:damage(n)`, `t:heal(n)`, `t:kill()`, `t:remove()`, `t:valid()`,
`t:distanceTo(x, y | entity)`, `t:moveToward(x, y, speed, dt)` and
`t:shoot(angle | {x =, y =} [, {speed, damage, kind, count, spread, radius,
lifetime, color, pierce}])`. `game:things([kind or tag])` and
`game:thingsNear(x, y, radius [, kind or tag])` find them.

Things are saved with a suspended run (quitting to the desktop), not in run
saves or restore points: rebuild them from `run.data` in `runStart`.

### Hazards

`spawn.hazard{...}` puts down a telegraphed danger: it shows a warning for
`warn` seconds (always drawn, whatever your mod does: hazards must be fair),
then hurts what `hurts` names for `active` seconds, once or every `tick`
seconds.

```lua
spawn.hazard{shape = "circle", x = player.x, y = player.y, r = 90,
             warn = 1.2, active = 0.3, damage = 2, hurts = "player", color = "#ff4040"}
spawn.hazard{shape = "line", x = 0, y = 300, length = 1100, angle = 0, r = 18,
             warn = 0.8, active = 1.5, tick = 0.25, damage = 1, hurts = "all"}
```

Shapes: `"circle"` (`r`), `"rect"` (`w`, `h`), `"line"` (`length` along
`angle`, `r` wide each side), `"ring"` (`inner` to `r`). `hurts`: `"player"`
(default), `"enemies"` or `"all"`. `onTrigger = fn(hazard, game)` runs when
the warning ends. It returns the hazard (a thing of kind `"@hazard"`).

### Projectiles and explosions

`register.projectile{...}` gives bullets a behaviour of their own:

```lua
local SEEKER = register.projectile{
  id = "seeker", pierce = 2, homing = 4,
  onHit = function(b, e, dmg) e.speed = e.speed * 0.8 return dmg end,
  onExpire = function(b) game:explode(b.x, b.y, 60, 2) end,
}
spawn.bullet{x = player.x, y = player.y, vx = 0, vy = -400, fromPlayer = true, kind = SEEKER}
```

Fields: `pierce` (enemies it passes through), `homing` (turn rate toward the
nearest target), `update(bullet, dt, game)` (return true to move it
yourself), `draw(bullet)`, `onHit(bullet, enemy, damage)` and
`onHitPlayer(bullet, player, damage)` (return the damage) and
`onExpire(bullet)`. `spawn.bullet` takes `kind`, `pierce` and `homing = true`
too, and a turret's `weapon.kind` fires them.

`game:explode(x, y, radius, damage [, {hurts = "enemies" | "player" | "all",
color, shake = "small" | "medium" | "large"}])` hurts everything of that side
in the circle (things too) and shows a burst.

## Statuses

A status is a named effect with stacks and a duration, on an enemy or on the
player: burns, curses, marks, buffs.

```lua
local SOUL = register.status{
  id = "soulBurn", name = {en = "Soul Burn", es = "Quemadura"}, color = "#a040ff",
  maxStacks = 5, duration = 4, tickInterval = 0.5,
  modifiers = {speed = -0.08, damageTaken = 0.1},   -- per stack
  onTick = function(e, stacks) e:damage(0.2 * stacks) end,
  onExpire = function(e) fx.particles(e.x, e.y, "#a040ff", 8) end,
}
hooks.on("bulletHit", function(dmg, b, e) e:applyStatus(SOUL) end)
```

* `register.status{...}` (while loading): `id`, `name`, `color`, `icon`
  (a texture for its pip), `maxStacks` (1), `duration` (seconds, 3; 0 or less
  lasts until cleared), `tickInterval` (seconds between `onTick`), and
  `modifiers = {speed, damageTaken, damageDealt}`: fractions per stack
  (`speed = -0.1` is 10% slower; `damageTaken = 0.2` takes 20% more). Callbacks:
  `onApply(target, stacks, magnitude)`, `onTick(target, stacks, magnitude)`,
  `onExpire(target)` and `draw(target, x, y, stacks)` (its pip over the target;
  a coloured dot by default).
* `e:applyStatus(name [, {duration, stacks = 1, magnitude = 1}])` adds stacks
  (up to `maxStacks`) and refreshes the duration; `magnitude` scales the
  modifiers. `e:status(name)` returns `{stacks, remaining, duration,
  magnitude}` or nil; `e:clearStatus(name)` removes it. `player` has the same
  three. `statuses.list()` names every status.
* The game's own effects work by name too: on enemies `"fire"` and `"poison"`
  (magnitude = damage per second), `"slow"` (magnitude 0 to 0.95, timed) and
  `"frost"` (a lasting chill); on the player `"poison"`.
* Speed modifiers move regular enemies only (bosses ignore slows, as with the
  game's own). An enemy's `damageDealt` counts on its touch and its bullets,
  not on boss attack patterns, lasers or hazards.
* Enemy statuses run on the enemies' clock (Time Warp slows them too).

## More content

Every `register.*` here is a table of fields; an unknown field is an error.
Names are `{en = ..., es = ...}` or a plain string; each call returns the
content's full name (`"<your mod id>:<id>"`).

### The `stats` table

Shop items, consumables, patches (and content packs) can change the player's
numbers without a line of code. `stats` maps a player field to a change:

| Value | Means |
|---|---|
| `2` or `"+2"` / `"-2"` | add |
| `"+10%"` / `"-10%"` | scale by 110% / 90% |
| `"x0.95"` | multiply |
| `"=3"` | set |

```lua
stats = {damage = "+10%", maxHp = 2, fireRate = "x0.95", walls = 3}
```

Any number field of the player works (`player:fields()` lists them); raising
`maxHp` heals by the same amount.

### Consumables

```lua
local MANA = register.consumable{
  id = "mana", name = "Mana Cell", color = "#4080ff",
  icon = "icons/mana.png",           -- or a function(x, y, radius, color); default: its initial
  weight = 6,                        -- drop chance next to the game's own 100
  modes = {"wave", "survival"},      -- empty: every mode
  stats = {damage = "+5%"},
  onPickup = function(player, game, x, y) fx.particles(x, y, "#4080ff", 20) end,
}
```

Random drops roll yours in with the game's; `spawn.consumable(MANA, x, y)`
drops one. The `pickup` hook sees its name as `kind`. Mod consumables do not
count in the lifetime consumable statistics.

### Shop items

```lua
register.shopItem{
  id = "core", name = "Spare Core", description = "+3 walls",
  cost = 12, costMult = 1.5, maxBuys = 5,   -- price x1.5 per purchase; 0 = no limit
  modes = {"wave"}, minWave = 3, color = "#78dca0", icon = "icons/core.png",
  stats = {walls = 3},
  onBuy = function(player, game, bought) end,
}
```

They appear after the shop's six rows (the list scrolls when it grows past
them). Purchases go through the `shopBuy` hook (its index counts from 7 for
yours) and the run statistics, and are saved with the run.

### Active [Q] abilities

A power-up can have an ability on the [Q] key:

```lua
register.powerup{
  id = "nova", name = "Soul Nova", legendary = true,
  active = {cooldown = 12, activate = function(player, level, game)
    game:explode(player.x, player.y, 160, 3)
    -- return false to say it did not fire (no cooldown)
  end},
}
```

It sits on the [Q] strip with the game's own, with its cooldown.

### Roguelite patches

```lua
register.patch{
  id = "ward", name = "KB Soul Ward", description = "+2 integrity; heals between rooms",
  color = "#a040ff", icon = "icons/ward.png",
  weight = 1,          -- chance in a draft; a game patch weighs 1
  minFloor = 2,
  stats = {maxHp = 2},
  onInstall = function(player, game) end,
  update = function(player, dt, game) end,   -- every frame of a run that has it
}
```

They are offered on patch pedestals and /pkg stalls with the game's own,
appear everywhere installed patches are listed, and are saved with the run
(by name: a run whose mod is gone just loses them). `player:hasPatch(name)`
checks for one (a game patch by its name, `"rrtOverclock"`).

### Survival events

```lua
register.survivalEvent{
  id = "storm", name = "Packet Storm", hint = "Survive the storm!",
  color = "#40c0ff",
  weights = {boot = 0, runtime = 20, overload = 25, panic = 25},  -- per phase
  duration = 20, warmup = 2,
  reward = "sctStandard",            -- a Data Cache on success (false: none)
  onStart = function(ev, game) ev.data.hits = 0 end,
  update = function(ev, game, dt)    -- "success" / "fail" end it; reaching duration succeeds
    if ev.data.hits > 10 then return "fail" end
  end,
  onFinish = function(ev, game, success) end,
  tracker = function(ev, game) return ev.data.hits .. " hits" end,   -- the HUD card's line
  fraction = function(ev, game) return 1 - ev.live / ev.limit end,   -- its bar
}
```

They join the random event draw by their weights (never twice in a row), with
the game's banner and HUD card. `ev` has `name`, `elapsed`, `live` (seconds
since the warmup ended), `warmup`, `limit`, `phase` and `data` (a table of
yours for this event). The `survivalEvent` hook can veto one by its name. A
running event is not saved with the run (the game's aren't either).

### Achievements

```lua
local SLAYER = register.advancement{id = "slayer", name = "Soul Slayer",
  description = "Raise 100 allies", goal = 100, hidden = false, icon = "icons/slayer.png"}
hooks.on("enemyDeath", function(e) advancements.progress("slayer") end)
```

`advancements.progress(id [, amount])` (true when that unlocked it),
`advancements.grant(id)` and `advancements.get(id)` (`{progress, goal,
unlocked}`). They are your mod's own: kept per profile, shown in MODS.EXE's
Achievements tab with a toast when one unlocks, and they unlock in any run,
cheated or not. They never touch the game's advancements or their rewards.

## In-run UI

### Screens

`ui.open{...}` puts a screen of yours over the run: a menu, a shop, a map, a
minigame. While it is open the run holds still (unless `pause = false`) and
the player's gameplay input (shooting, dash, walls, [Q]) waits.

```lua
local s = ui.open{
  draw = function(w, h)           -- screen coordinates of the HUD (draw.*, ui.* widgets)
    ui.panel(w / 2 - 150, h / 2 - 80, 300, 160, {title = "TERMINAL", color = "#40ff80"})
    if ui.button(w / 2 - 60, h / 2 + 20, 120, 30, "CLOSE") then s:close() end
  end,
  update = function(dt) end,      -- every frame it is open
  click = function(x, y, button) end,   -- a click no widget took ("left" / "right")
  onClose = function() end,
  pause = true, closeOnBack = true,     -- Esc / gamepad B closes it
  layer = "hud",                  -- or "screen": raw screen pixels, over everything
}
```

It returns `{id, close = fn, isOpen = fn}` (`s:close()`, `s:isOpen()`);
`ui.close(s)`, `ui.isOpen(s)` and `ui.closeAll()` (your mod's) work too.
Screens are never saved: a resumed run reopens what it needs in `runStart`.

### Widgets

Immediate mode: call them every frame you draw, and they return what the
player did. They work in a screen's `draw`, a HUD card, an app's `draw` and
`drawHud`, with the mouse or a gamepad (A clicks where the pad's cursor
points).

* `ui.panel(x, y, w, h [, {title, color}])` -> the y below its title
* `ui.button(x, y, w, h, label [, {color, enabled}])` -> true the frame it is clicked
* `ui.label(text, x, y [, {size, color, align = "left" | "center" | "right", width}])`
  (wraps to `width`) -> the height it used
* `ui.progress(x, y, w, h, fraction [, color])`
* `ui.checkbox(x, y, label, checked)` -> the new value
* `ui.slider(x, y, w, value, min, max)` -> the new value
* `ui.pointer()` -> x, y, pressed, down

### Dialogue, choices and cutscenes

```lua
ui.dialogue{
  lines = {
    {speaker = "KERNEL", text = "You are not supposed to be here.", portrait = KERNEL_TEX, color = "#ff4060"},
    {speaker = "YOU", text = "Then why did you leave the door open?"},
  },
  choices = {"Fight", "Flee"},           -- on the last line (keys 1..9 work too)
  onChoice = function(i) end, onDone = function() end,
}
ui.choose{title = "Pick a blessing", options = {
  {title = "Fury", description = "+20% damage", icon = FURY_TEX, color = "#ff6040"},
  {title = "Ward", description = "+3 integrity"},
}, onPick = function(i) end, allowSkip = false}
ui.cutscene{shots = {
  {duration = 2, draw = function(t, w, h) draw.text("YEAR 2049", w / 2 - 80, h / 2, 30, "#ffffff") end},
  {duration = 3, draw = function(t, w, h) draw.texture(CITY, w / 2, h / 2, {w = w}) end},
}, skippable = true, onDone = function() end}
```

Space / Enter / a click (or A) advance and confirm; Esc / B skips (when
`skippable`, default true; `ui.choose` only with `allowSkip`, and `onPick`
then gets nil). Each returns its screen.

### Toasts and banners

`ui.toast(text)` shows a notification (over a run, or on the desktop).
`ui.banner(title [, subtitle, color, seconds])` shows a big line over the run.

### HUD cards

```lua
register.hudCard{id = "souls", title = "SOULS", color = "#a040ff", height = 34,
  draw = function(x, y, w, h)
    ui.progress(x, y + 4, w, 8, run.data.souls / 100, "#a040ff")
    ui.label(run.data.souls .. " / 100", x, y + 16, {size = 12})
  end, classic = true}
```

A card of yours in the HUD's run column (16:9, under the mode's own card), or
at the top right in the classic and legacy HUDs (`classic = false` keeps it
out of those). `measure = fn(w) -> height` sizes it every frame instead of
`height` (0 hides it that frame: a mode's card can stay out of other runs).
`hud.hide("run")` hides them with the rest of the run column.

### Pause-menu actions

`register.pauseAction{id = "skipIntro", name = "Skip the intro", onClick =
fn(game)}` adds a button to a MODS tab in the pause menu (shown only when
some are registered).

## Camera and time

**Camera.** `camera.zoom = 2` zooms into the arena (1 to 3; never out: the
arena is all there is). `camera.x` / `camera.y` set where it looks (it stays
inside the arena on its own), `camera.follow(true [, lerp])` keeps the player
centred (`lerp`: how fast it catches up, per second; 0 snaps),
`camera.reset()` shows the whole arena again. Aiming, the cursor and the
gamepad follow the camera. `camera.toScreen(x, y)` gives the screen point an
arena point is drawn at, `camera.toWorld(x, y)` the reverse. Each run starts
with the whole arena; the camera only applies to the 2D arena (not PvP or 3D
worlds).

```lua
hooks.on("bossSpawn", function(boss) camera.zoom = 1.6 camera.follow(true, 6) end)
hooks.on("bossDeath", function() camera.reset() end)
```

**Time.** `time.scale` (0.1 to 2) runs the whole world faster or slower;
`time.enemyScale` (0 to 2) only the enemies and their shots (0 freezes them).
`time.hitstop(seconds [, scale])` freezes the world for a beat and
`time.slowmo(seconds, scale [, ramp])` slows it down (easing back with `ramp`),
like the game's own hit stop and slow motion. All of it resets with each run.

## Commands

```lua
register.command{name = "souls", help = {en = "Shows your souls", es = "Muestra tus almas"},
  run = function(args)              -- the words typed after it
    return "You have " .. (mod.storage.souls or 0) .. " souls"   -- or a list of lines
  end}
```

The Help terminal (HELP.EXE) runs it on the desktop and lists it under
`help`.

## Content packs

A mod can be data only: put JSON files under `content/` in its folder (any
depth). Each file holds one entry or a list; `type` says what it registers
and every other field is that `register.*` call's table:

```json
[
  {"type": "powerup", "id": "grit", "name": "Grit", "maxLevel": 3, "stats": {"maxHp": "+2"}},
  {"type": "shopItem", "id": "core", "name": "Spare Core", "cost": 10, "stats": {"walls": 2}},
  {"type": "consumable", "id": "mana", "color": "#4080ff", "weight": 5, "stats": {"damage": "+5%"}},
  {"type": "enemy", "id": "brute", "base": "etCube", "hp": 9, "speed": 70, "color": "#ff8040"}
]
```

Types: `powerup`, `enemy`, `boss`, `thing`, `projectile`, `status`,
`consumable`, `shopItem`, `patch`, `survivalEvent`, `advancement`, `theme`
(see [Interface themes](#interface-themes)), and `roster`, which is `roster.add` for a pack: `{"type": "roster", "mode":
"wave", "enemy": "brute", "chance": 0.1, "fromWave": 3}` (a bare enemy id is
the pack's own; `minTime` and `minFloor` work too). Files load
in name order, after `main.lua` (if any), still while the mod loads. A mod
with a `content/` folder needs no `main.lua` at all. JSON cannot hold
functions, so what a pack registers does what its fields (and `stats`) say; a
script can add the behaviour (`hooks.on`, `override.*`). A bad entry fails the
mod with the file's name.

## Difficulty

`difficulty.scale{enemyHp, enemyDamage, enemySpeed, spawnPace, eliteChance,
bossCooldown}` multiplies the game's difficulty levers for this run, on top
of the profile's difficulty (`spawnPace` 1.5 spawns 50% faster, `bossCooldown`
0.8 makes bosses attack more often). Each run starts at 1 everywhere: set it in
`runStart`. `difficulty.get()` returns the profile (`"gdHard"`...) and the
scale in force.

## More of the player

* The dash is tunable per run: `player.dashBurstMult` (speed multiple during
  the burst, 3.4), `player.dashTime` (seconds of burst, 0.16) and
  `player.dashRecharge` (seconds between dashes, 2.5). The HUD's dash meter
  follows them.
* `player:hurt(amount, {cause = "Lava"})`: when that hit is lethal the run ends
  at once and the crash screen reads "Terminated by Lava".

## New power-ups and enemies

```lua
local overdrive = register.powerup{
  id = "overdrive",                       -- becomes "<your mod id>:overdrive"
  name = {en = "OVERDRIVE.exe", es = "SOBREMARCHA.exe"},
  description = {"+10% damage", "+20% damage", "+30% damage"},  -- per level
  maxLevel = 3, legendary = false, color = "#ffcc33",
  family = "core", group = "none", modes = {"wave", "survival"},
  icon = function(color) draw.circle(16, 16, 10, color) end,       -- 32x32 box
  onPickup = function(player, level, game) player.damage = player.damage * 1.1 end,
  update = function(player, level, dt, game) end,          -- every frame while owned
  onHit = function(bullet, enemy, damage, level) return damage * 1.1 end,  -- player shots
}

local bouncer = register.enemy{
  id = "bouncer", name = "bouncer",       -- name: its in-world process label
  base = "etCube",                        -- AI and body it starts from
  hp = 2, radius = 11, speed = 70, contactDamage = 2, color = "#40c0ff",
  coins = 3, xp = 2,
  config = {attack = {fireRate = 1.5}},   -- any enemies.config() field
  update = function(e, dt, game) end,     -- return true to skip the base AI
  draw = function(e) draw.circle(e.x, e.y, e.radius, "#40c0ff") end,
}
roster.add("wave", bouncer, {chance = 0.15, fromWave = 3})
```

* Registration returns the new name, `"<mod id>:<id>"`. Use it anywhere a
  type or power-up name is taken: `spawn.enemy(bouncer, x, y)`,
  `player:powerUpLevel(overdrive)`, filters that return enemy types, and so on.
* A power-up's `description` can be a single string, one string per level,
  `{en = {...}, es = {...}}`, or `function(level) return "..." end`. Its effect
  is its `onPickup` (runs on every pickup and upgrade), its `update` (every
  frame while the player has it) and `onHit` (each player bullet hit: return
  the new damage), plus any hooks you write that check
  `player:powerUpLevel(overdrive)`. Damage and healing done inside these three
  show up as this power-up's in the run statistics.
* A mod enemy's `base` must be a wave-mode type (`etCircle` ... `etMage`); it
  shows up in the sandbox's enemy list and in `enemies.types()`.
* `roster.add(mode, enemy, options)` mixes an enemy into a mode's spawns:
  `chance` per spawn (0-1), plus `fromWave` (wave), `minTime` (survival
  seconds) or `minFloor` (roguelite sector).
* `override.powerup(name, {maxLevel, legendary, color, family, group, modes,
  update, onHit})` changes a built-in power-up's registry entry and can add
  behaviour on top of its own; the `powerUpApply` hook replaces its pickup
  effect. `powerups.list()` and `powerups.get(name)` look them up.
* The `powerUpChoices` filter gets the three offered names and may return a
  list of names to offer instead.

There is room for 256 mod power-ups and 128 mod enemies across all loaded mods.
Saves store mod content by name, so a run saved with a mod keeps its power-ups
as long as that mod is loaded.

## Game modes

A mod can add whole game modes. They appear in **MODS.EXE > Game Modes** with
Launch and Continue buttons, and each gets an icon on the desktop that launches
it like the game's own modes (with a Continue / New Run prompt when a run is
saved). Every mode keeps its own saves.

```lua
local MODE = register.gamemode{
  id = "glass_cannon",
  name = {en = "Glass Cannon", es = "Cañón de Cristal"},
  description = {en = "...", es = "..."},
  base = "wave",          -- "wave", "survival", "roguelite" or "3d": the rules it starts from
  spawning = true,        -- false: the base mode spawns nothing by itself
  resumable = true,       -- false: quitting ends a run instead of saving it to resume
  icon = "icon.png",      -- optional desktop icon; color and desktop work the same way
  onStart = function(game, resumed) end,
}

hooks.on("waveEnemyCount", function(count)
  if run.active and game:isMode(MODE) then return count * 2 end
end)
```

* Every hook runs for every run, so a mode's rules check `game:isMode(MODE)`
  (`game.modMode` holds the mode's name during its runs).
* `spawning = false` stops wave mode from starting waves and survival's horde
  from spawning (its clock, events and bosses carry on), so your scripts decide
  what appears and when. It has no effect on the roguelite.
* `icon`, `color` and `desktop` are the desktop-icon options of `register.app`
  (see the option table in [Apps](#apps)): a texture or model for the icon, its
  accent color, and `desktop = false` to leave the icon off (the mode stays in
  MODS.EXE). Without an `icon` the icon is a play triangle on a small screen;
  without a `color` it takes its base mode's color (Play blue, Survival orange,
  Roguelite teal). Mode icons come first among the mod icons, in registration
  order, tagged MOD.
* **Quitting is never a loss**, in any mode. A run that is quit and cannot be
  resumed ends with `runEnd(game, false)` and counts no death.
* `resumable = false` turns off resuming a run you quit: leaving a run of the
  mode (the pause menu's exit, Q in a 3D world's pause, `world3d.exit()` in a
  3D mode, or closing the game) ends it instead of saving it, the exit prompt
  says so, and the mode's desktop icon and MODS.EXE never
  offer the Continue / New Run prompt for a saved run. Its
  [restore points](#restore-points) are separate and keep working. A script
  can decide for one run with `run.resumable` (see below).
* `base = "3d"` makes a mode that plays entirely in a first-person 3D world
  (see [3D worlds](#3d-worlds)): it launches into an empty world that the
  world3d hooks build, `spawning` is off, and finishing the world with
  `world3d.finish(true)` wins the run. Example: `arena_3d`.
* To change an **existing** mode instead, write the same hooks without a mode:
  check `game:isMode("survival")` and so on (see the `chaos_engine` example).

### Restore points

When a run dies, the crash screen can offer **CONTINUE**: the run starts again
from its last checkpoint and spends a restore point, drawn as a save platter in
the meters on the crash, pause and victory screens. How many a run gets depends
on the profile's difficulty and the base mode (wave: unlimited / 3 / 1 / 0 from
Easy to Nightmare; survival and roguelite: 3 / 1 / 0 / 0), and each base mode
saves its checkpoint at fixed points (the start of a boss block, a sector, a
survival phase). A mode can take all of it over:

```lua
register.gamemode{
  id = "gauntlet", base = "3d",
  restorePoints = 2,           -- 2 on every difficulty
  -- restorePoints = false       no restore points at all
  -- restorePoints = "unlimited"
  -- restorePoints = {easy = "unlimited", medium = 3, hard = 1}   nightmare keeps the base 0
  restoreGlyphs = true,        -- false: continues work, but no meter and no loss animation
}
```

* `restorePoints = false` switches the system off for the mode: no checkpoint
  is ever written (not by the base mode, not by a script), the crash screen
  offers no CONTINUE, and no restore-point meter or animation is drawn. A
  number (0 to 1000) or `"unlimited"` is the budget on every difficulty; a
  table sets it per difficulty, and a difficulty it leaves out keeps the base
  mode's. `0` keeps the meter, reading NONE LEFT, like Nightmare. Anything
  else is an error that names it.
* A run that is past its win (endless waves, endless loops, Overtime) still has
  no restore points, whatever the budget.
* `run.restorePoints` is the run's side of it, read live: `enabled` (the mode
  has the system), `max` and `left` (`math.huge` when unlimited), `used`,
  `saved` (a checkpoint is there for CONTINUE to resume), `offline` (past the
  win) and `glyphs` (the meters are drawn). `used` can be set (a whole number
  from 0): giving one back or taking one away also updates the checkpoint, so
  the crash screen agrees. The rest are read-only.
* `run.restorePoints.save([label])` makes the run as it stands now, with its
  `run.data`, the checkpoint CONTINUE resumes, and returns whether it was
  written (not when the mode has none or a budget of 0, or the run is past its
  win; with none `left` it is written, but CONTINUE stays off). `label` (`"ROUND 3"` or
  `{en = "ROUND 3", es = "RONDA 3"}`) is what the button names: CONTINUE (ROUND
  3); without one it names the base mode's wave, sector or clock.
  `run.restorePoints.clear()` drops the checkpoint. A 3D mode has no
  checkpoints of its own, so its script saves them; CONTINUE then opens a fresh
  world with `resumed = true` (rebuild it from `run.data`, as on Continue after
  quitting), and `restorePointUsed` tells it a restore point paid for it.
* The `checkpoint` hook runs before each of the base mode's own checkpoints;
  returning `true` skips it. To save your own instead, call
  `run.restorePoints.save(label)` from that hook and return `true`.
* `hud.hide("restorePoints")` hides the meters and the loss animation for the
  run, in any mode (`hud.hide("all")` leaves them). `restoreGlyphs = false`
  does it for every run of the mode.
* Continue after **quitting** (the Continue / New Run prompt) is a saved run,
  not a restore point, and is not affected by any of this: `resumable` turns
  it off.

## Textures, sounds and cosmetics

Files load from your own mod folder (paths relative to it; `..` is refused).

* `assets.texture("sprites/ship.png")` returns a texture (`tex.width`,
  `tex.height`); draw it inside a draw hook with
  `draw.texture(tex, x, y [, {w = .., h = .., rotation = degrees, tint = color,
  origin = "center" | "topleft"}])`.
* Textures are images in any of these formats: **PNG, JPG, BMP, TGA, GIF,
  QOI, PSD** (the merged image), **HDR, PIC, PPM/PGM, DDS, KTX, PKM, PVR** and
  **ASTC** (the last four are GPU-compressed formats, which load only where
  the graphics card supports them). Upper or lower case in the extension does
  not matter. A video works as a texture too (see [Videos](#videos)).
* An **animated GIF** plays by itself
  anywhere a texture goes (`draw.texture`, `override.texture`, cosmetics), at
  the frame delays saved in the file, looping. Every copy on screen shows the
  same frame. `tex.frames` is its number of frames and `tex.duration` one loop
  in seconds (1 and 0 for a still image). To pick the frame yourself, pass
  `frame = n` (1 is the first; it wraps) or `time = seconds` (the frame that
  far into the animation) to `draw.texture`. A delay under 2/100 s plays as
  1/10 s, as in web browsers. GIF transparency is all or nothing per pixel, so
  use a PNG for soft edges.
* `assets.sound("sfx/zap.wav")` returns a sound: `snd:play([volume, pitch])`.
  WAV, OGG, MP3, FLAC or QOA. For music, and any sound that should loop or
  be paused, use `assets.music` (see [Music](#music)).
* `override.texture(target, file [, {scale = 1.2, rotate = true}])` draws an
  image or a video instead of one of the game's bodies. Targets: `"player"`, `"enemy:<type>"`,
  `"boss:<id>"`, `"bullet:player"`, `"bullet:enemy"`, `"powerup:<name>"` (its
  icon) and `"desktop"` (the wallpaper), plus the 3D-world targets `"boss3d"`,
  `"satellite3d"`, `"entity3d:<tag>"`, `"projectile3d:player"`,
  `"projectile3d:enemy"` and `"pickup3d:<kind>"` (see [3D worlds](#3d-worlds)). `scale` multiplies the body's size;
  `rotate` turns the image with the body. A wallpaper hides the desktop cube
  unless you pass `{cube = true}`: then the cube (in the player's cube skin)
  keeps floating over your image and can still be grabbed and spun. Pass
  `nil` instead of the file to put the game's own look back.
* A wallpaper is drawn from the screen's top-left corner and scaled to the
  screen dimensions without repositioning its artwork. The desktop cube is
  independent of the wallpaper's placement.
* `override.sound(name, file)` replaces one of the game's sounds (`shoot`,
  `enemyHit`, `enemyDeath`, `playerHit`, `coinPickup`, `powerUp`, `bossSpawn`,
  `explosion`, `wallPlace`, `teleport`, `menuNav`, `menuSelect`,
  `waveComplete`, `shield`, `gameOver`, `buy`, ...). WAV, OGG, MP3, FLAC or QOA.
* `override.music(track, file)` replaces a music track: `"menu"`, `"wave"`,
  `"powerUp"`, `"boss"`, `"survival"` or `"roguelite"`, or a story cinematic's
  score: `"storyIntro"`, `"storyRootAccess"`, `"storyBelow"` or `"storyUptime"`.
  OGG, MP3, WAV, FLAC, QOA, or the tracker formats XM and MOD. Survival and
  roguelite runs play their own theme, not `"wave"`; a boss fight in any mode
  plays `"boss"`. Switching tracks takes a fraction of a second, and a track
  starts from its top every time it comes in. The built-in wave, survival,
  roguelite and boss themes change their arrangement with the run (the wave
  number, the survival phase, the roguelite folder, the boss's phases) and
  muffle while the player's integrity is critical; a replacement plays as it
  is, looping from its end back to its start. A score plays once from the top in
  time with its cinematic (fast-forwarding speeds it up) and does not loop, so
  make it as long as the cinematic.
* `register.cosmetic{kind = "player" | "bullet" | "desktop" | "cube", id = "neon",
  name = "Neon", description = "...", colors = {"#ff00ff", "#00ffff", "#ffffff"},
  texture = "skins/neon.png", scale = 1.2, rotate = true}` adds a cosmetic the
  player equips in **MODS.EXE > Cosmetics**, or in the Shop's **MODS** tab
  (shown while a loaded mod has cosmetics). `colors` is a palette for the
  built-in shapes (player: body, trim, core; bullets: body, glow, trail); a
  `texture` or a `model` (see 3D models below) replaces the drawing. Desktop
  cosmetics take a texture (the wallpaper; `cube = true` keeps the desktop
  cube over it, hidden by default) and/or a model. Desktop wallpapers and cube
  models have independent equip slots, so both can be active at once. The
  `cube` kind is for a mod model that replaces the desktop cube; the `desktop`
  kind remains compatible with older combined wallpaper/cube cosmetics.

Equipped mod cosmetics are remembered per profile and come back whenever the
mod is loaded. In PvP everyone in the lobby sees each player's mod ship and
bullet cosmetics.

## Videos

* `assets.video("clips/intro.mpg")` returns a video. A video goes everywhere
  a texture goes: `draw.texture(clip, x, y, {...})`, `override.texture`,
  `register.cosmetic{texture = ...}`, app and mode icons, `draw3d.billboard`,
  `draw3d.texture` (a screen in a 3D world) and `shader:set` (a file name
  ending in `.mpg` works there too, as with `assets.texture`).
* **Format.** Videos are **MPEG-1 in an `.mpg` file** (with MP2 sound). The
  game decodes them itself, so a video plays the same on every system. Convert
  any other video (MP4, MOV, WebM, ...) with ffmpeg:

  ```
  ffmpeg -i in.mp4 -c:v mpeg1video -q:v 4 -c:a mp2 -b:a 192k -f mpeg out.mpg
  ```

  (`-an` leaves the sound out, `-s 640x360` shrinks the picture, and a lower
  `-q:v` raises the quality. MPEG-1 takes the usual frame rates only: 24, 25,
  30, 50 or 60.) Any other video file is an error that gives this command.
* **A video plays while it is on screen.** It starts the first time it is
  drawn and holds still, sound and all, while nothing draws it (a closed app,
  a hidden wallpaper), so it costs nothing then. It runs on the wall clock,
  like a GIF, and every copy on screen shows the same picture: one file is one
  playback, whichever handle drew it. Until it first plays it shows its first
  picture.
* **A paused game is still drawn** under its pause screen (a run and a 3D
  world alike), so a video it draws keeps playing, sound and all. Pause it
  yourself while `world.paused` is true (or the run is paused) and play it
  again after; the `media` example's Billboard Plaza does.
* It loops unless `clip.loop = false`; it then stops on its last picture and
  `clip.ended` turns true.
* `clip:pause()`, `clip:play()` (an ended video starts over), `clip:stop()`
  (pauses on the first picture) and `clip:seek(seconds)`.
* Fields: `width`, `height`, `duration` and `time` (seconds), `fps`,
  `playing` (moving right now), `paused`, `ended` and `hasAudio`. `loop`
  (true) and `volume` (1, up to 4) can be set.
* Its sound follows the game's sound volume. While a video's sound plays, the
  game's own music waits, and goes on when it stops.
* Decoding costs time every frame: up to 1280 x 720 at 30 frames a second is
  comfortable; 1080p works but is heavy.

## Music

* `assets.music("music/theme.ogg")` returns a music track, streamed from the
  file: OGG, MP3, WAV, FLAC, QOA, XM or MOD.
* `theme:play()` (from where it was paused, else from the start),
  `theme:pause()`, `theme:stop()` and `theme:seek(seconds)`.
* Fields: `duration`, `time`, `playing` and `paused`; and settable `volume` (1,
  up to 4), `loop` (true), `pitch` (1), `pan` (0; -1 is left, 1 right) and
  `layer` (false).
* It follows the game's music volume. While it plays (or is paused) the
  game's own music waits, and goes on from where it was when yours stops;
  playing a second track stops the first. A track with `layer = true` plays
  over the game's music instead (ambience, a drone under a boss), and any
  number of those can play at once.
* A track started during a run stops when the run leaves the screen (game
  over, quitting to the desktop); one started on the desktop (in an app, say)
  plays on until you stop it.

## Fonts

* `assets.font("fonts/pixel.ttf" [, {size = 32, smooth = true, chars = "..."}])`
  returns a font: **TTF** or **OTF**, **FNT** (BMFont, with its page images
  beside it) or **BDF**.
* Give it to `draw.text`, `draw.textWidth` or `draw3d.text` as the last
  argument, alone or in a table with the letter spacing:
  `draw.text("Score", 10, 10, 24, "#ffffff", font)` or
  `draw.text("Score", 10, 10, 24, "#ffffff", {font = font, spacing = 2})`.
  Text in your own font may be 1 to 400 pixels tall.
* A TTF or OTF is made at `size` pixels (4 to 256, 32 by default) and scaled
  from there, so text at that size is the sharpest; `font.size` tells it. FNT
  and BDF fonts keep their own size. `smooth` (true for TTF/OTF, false for
  FNT/BDF) blends the scaled edges rather than keeping hard pixels.
* Every font carries ASCII and the accented letters of Western European
  languages (what the game's own text uses). `chars` adds any others it should
  have, for example `chars = "ĄĘŁŃŚŹŻ"` or a whole alphabet.

## Data files

Data your mod ships with (levels, dialogue, tables) reads from its folder (or
any absolute path):

* `assets.text("data/story.txt")` returns a file's contents as a string.
* `assets.json("data/levels.json")` returns its value: tables, numbers,
  strings and booleans. A malformed file is an error with the line and column.
* `assets.exists(path)` tells whether a file or folder exists in your mod.
* `assets.list([folder])` returns the names in a folder of your mod (its top
  folder without one), sorted; folder names end with `/`.

Lua files load with `require`; `io` reads and writes anything else.

## 3D models

Models load from your folder like textures and go wherever a texture goes:
the game's bodies, cosmetics, and your own drawing.

* `assets.model("models/ship.glb")` returns a model. Formats: **GLB/glTF**
  (Blender's glTF 2.0 export; the best choice), **OBJ** (with its `.mtl`
  beside it), **IQM**, **VOX** (MagicaVoxel) and **M3D**. `mdl.width`,
  `mdl.height` and `mdl.depth` are its size in its own units,
  `mdl.animations` lists its animations by name and
  `mdl:duration(animation)` is one loop of one, in seconds.
* A model's **up is +Y and its front is +Z** (glTF's convention, which is
  what Blender writes). The arena is seen from above, so an unturned model
  faces the bottom of the screen.
* One light from the upper left shades the model over its own colours
  (material colour, texture and vertex colours all show). `lit = false`
  draws the flat colours instead, which suits glowing things. Pixels under
  2% alpha are cut out.
* `override.model(target, model [, options])` draws the model instead of one
  of the game's bodies. The targets are those of `override.texture` (`"player"`,
  `"enemy:<type>"`, `"boss:<id>"`, `"bullet:player"`, `"bullet:enemy"`,
  `"powerup:<name>"`, and the 3D-world targets) plus `"cube"`: the desktop cube, which the model
  replaces as it tumbles and is dragged, and also as the orbital cube that
  follows the player. The model's footprint (its width or length seen from
  above, whichever is larger) is fitted to the body. `nil` instead of the
  model puts the game's own look back.
* `draw.model(model, x, y [, options])` draws one in any draw hook or app,
  centred on x, y. `size` is its footprint in pixels (64 by default), or
  `scale` sets pixels per model unit; `facing` is where its front points, in
  degrees (0 right, 90 down, the default); `time = seconds` or `frame = n`
  (1 is the first) pick the animation frame.
* `register.cosmetic{..., model = "skins/ship.glb"}` takes a model and the
  same options: a 3D ship, 3D bullets, or a desktop cube of your own.

| Option | Default | What it does |
|---|---|---|
| `scale` | 1 | multiplies the body's size (`override.model`, cosmetics) |
| `rotate` | false | the front turns to where the body moves (`override.model`, cosmetics) |
| `tilt` | 0 | degrees the camera leans back from straight above; 30 shows the front and sides |
| `yaw` | 0 | degrees turned about the model's up axis (for a model whose front is not +Z) |
| `pitch`, `roll` | 0 | tip the model forward, lean it sideways (degrees) |
| `spin` | 0 | keeps turning it about its up axis, degrees per second |
| `animation` | the first | a name or a number (1 is the first); `false` holds the rest pose |
| `speed` | 1 | animation speed |
| `fade` | 0.2 | seconds a change of animation crossfades; 0 switches at once |
| `key` | none | `draw.model` and `draw3d.model`: a string or number naming what you draw, so it crossfades when its animation changes |
| `lit` | true | shaded by the light; `false` for flat colours |
| `tint` | white | a colour multiplied over the model |

Animations are skeletal (a mesh skinned to an armature) in GLB/glTF, IQM and
M3D. They loop at 60 frames per second, which is the speed glTF and M3D
animations were authored at, and up to 128 bones move a mesh. Each enemy
starts its animation at its own point, so a crowd does not flap in step.

**Crossfades.** When a body's animation changes, it blends from the pose on
screen into the new animation over `fade` seconds instead of jumping. The
bodies the game draws do this on their own: calling `override.model` again
with another `animation` crossfades every player, enemy or boss wearing it,
and so does setting a 3D entity's `modelAnim` (its `modelFade` sets the
time). `draw.model` and `draw3d.model` draw a fresh copy every call, so give
what you draw a `key` (a string or a number; an enemy's `id` works well, and
each mod's keys are its own) and it crossfades the same way when the
`animation` you pass changes. The rest pose (`animation = false`) fades in and
out like any animation.

Every copy on screen is drawn on its own, so keep enemy models light: a few
hundred triangles each is plenty.

## 3D worlds

The game has a first-person 3D mode (the Orbital Commander boss fight). Mods can
enter it, change it, or build a whole game in it: a world of platforms, enemies
that walk, orbit or shoot, pickups, a tunable weapon and your own HUD. The
`arena_3d` example has both: **Cube Siege**, a complete mode built this way,
and changes to the game's own 3D fight. The `media` example's Billboard Plaza
puts videos and images on screens and billboards in a world.

```lua
hooks.on("world3dStart", function(world, resumed)
  world3d.arena{radius = 300}          -- an empty world already has a solid floor
  world3d.spawn{tag = "cube", x = 40, y = 6, z = 0, hp = 40, ai = "chase",
                shape = "cube", contactDamage = 10, gravity = true}
end)
```

### Getting into a world

* **A 3D game mode:** `register.gamemode{base = "3d", ...}` (see
  [Game modes](#game-modes)). Launching it goes straight into an **empty**
  world: no boss, nothing spawned, no 2D arena. The script builds everything.
  Winning the world wins the run (the victory screen); losing it ends the run
  through the death screens; leaving it quits the run (see Leaving below).
* **From a 2D run:** `world3d.enter{boss = false, bossId = 7, keepHp = true}`
  opens a world at the end of the frame, through the fade to black. With
  `boss = true` it is the game's own boss fight (`bossId` 7, the Orbital
  Commander, is the authored one). `keepHp` carries the run's HP in and back
  out. When the world ends the run carries on (a won boss fight completes the
  boss wave). It is an error outside a run, while a world is already active,
  or in a run that is a 3D mode already.
* **Leaving:** `world3d.finish(true)` (or `false`, or `"won"` / `"lost"`; no
  argument means won) ends the world as won or lost, and `world3d.exit()` leaves
  it (`"exit"`). In a 3D mode leaving the world is quitting the run, never a
  loss: back to the desktop, the run saved to resume like Q at the pause
  (unless the mode is not `resumable`). Both take effect at the end
  of the frame. A world also ends by itself when the player dies
  (`rules.exitOnPlayerDeath`), when the boss dies (`rules.exitOnBossDeath`) and
  when `rules.timeLimit` runs out (a loss, or a win with `rules.timeLimitWins`).
* **Pausing:** Esc pauses a world (nothing ticks); **Q** while paused quits to
  the desktop (`world3dEnd` gets `"exit"`).

`world3d.active()` says whether a world is being played. Every other `world3d`
function except `enter` is an error outside one:
`world3d.spawn needs an active 3D world (world3d.active() is false)`.

### The world

`world3d.world` (also the first argument of the world3d hooks) is the world;
`world3d.player` is a shortcut for `world.player`. Like `game` and `player`
they read and write by field name, and vectors are live views:
`world3d.player.pos.y = 50`. `world:fields()` lists them.

| Field | |
|---|---|
| `score`, `kills`, `wave`, `timeElapsed`, `spawnPos` | writable counters and the world's clock (`spawnPos` is where the player reappears when a script saves them from a fall) |
| `active`, `result`, `pendingResult`, `paused`, `quitRequested`, `resumed`, `startFired` | read-only state |
| `bossEnabled`, `bossId`, `modeKey`, `carryHp`, `nextId` | read-only. `modeKey` is your mode's name (`"my_mod:cube_siege"`) in a 3D mode and `""` otherwise |
| `boss.*` | the boss (below). `boss.health` and `boss.maxHealth` are read-only |
| `arena.*` | `radius`, `boundsRadius`, `gravity` (negative pulls down), `deathPlaneY`, `skyColor`, `floorColor`, `wallColor`, `environmentIntensity`, `drawFloor`, `drawWalls`, `solidFloor`, `floorY` and `platforms[i]` |
| `camera.*` | `position`, `target`, `up`, `fovy`, `yaw`, `pitch`, `shakeTime` (`shake`, the strength drawn, is worked out from it every frame) |
| `player.*` | `pos`, `vel`, `health`, `maxHealth`, `speed`, `sprintMultiplier`, `jumpForce`, `jumpsRemaining`, `maxJumps`, `grounded`, `radius`, `invulnTimer`, `hitInvuln`, `canJump`, `gravityScale` |
| `player.weapon.*` | `ammo`, `maxAmmo`, `damage`, `fireRate`, `fireTimer`, `projectileSpeed`, `projectileRadius`, `projectileColor`, `spread`, `pellets`, `automatic`, `reloadTime`, `reloadTimer`, `infiniteAmmo` |
| `rules.*` | `exitOnBossDeath`, `exitOnPlayerDeath`, `timeLimit`, `timeLimitWins`, `allowReload`, `autoFire`, `mouseSensitivity` |

Units are the game's 3D units: the player walks at 75, a world's arena has radius
500 (the player is kept within 450 of the centre) and gravity is `-20`. About the weapon: `spread` is a cone half-angle in
degrees, applied to each pellet; `automatic = true` keeps firing while the
button is held; the `autoFire` rule fires whenever the weapon is ready, with no
input; `fireRate` is the seconds between shots. `hitInvuln` is the invulnerable
time after a hit (0 by default). Colours are `"#rrggbb[aa]"`, `{r, g, b [, a]}`
or `{r =, g =, b =, a =}` as everywhere.

```lua
local w = world3d.player.weapon         -- a shotgun
w.pellets, w.spread, w.damage, w.fireRate = 8, 4, 12, 0.7
w.maxAmmo, w.ammo, w.reloadTime = 24, 24, 1.2
```

### The arena and platforms

```lua
world3d.arena{radius = 320, sky = "#0b1020", floor = "#1c2333", wall = "#39435c",
              gravity = -20, deathPlaneY = -50, theme = "empty"}
world3d.platform{x = 60, y = 0.5, z = 60, w = 20, h = 1, d = 20, color = "#40ff80",
                 jumpPad = true, jumpForce = 900}
```

* `world3d.arena{...}` keys: `radius`, `bounds`, `sky`, `floor`, `wall`,
  `gravity`, `deathPlaneY`, `floorVisible`, `wallsVisible`, `solidFloor`,
  `floorY` and `theme` (`"default"`, `"space"` or `"empty"`). A `theme` is
  applied first: it rebuilds the platforms from that theme's layout and resets
  every other key (`solidFloor`, `floorY`... included) before yours apply.
  `radius` also sets how far the player can walk (`bounds`, 0.9 x radius)
  unless you give `bounds` too.
* `world3d.platform{x, y, z, w, h, d, color, moving, moveSpeed, jumpPad,
  jumpForce, rotationSpeed}` adds a platform and returns its number (1-based,
  the index in `world.arena.platforms`). `w`, `h`, `d` are the **full** size
  (20 x 2 x 20 by default); `world.arena.platforms[i].size` holds half of it.
  `world3d.clearPlatforms()` removes them all.
* **The floor.** With `solidFloor` the plane at `y = floorY` is ground: the
  player and any entity with `gravity` land on it, and shots fly on through it
  (they do not die on it). `world3d.raycast` reports it as `"floor"`. It is on
  in an `"empty"` world, the default of a mod's world (`floorY` -9.5, the top
  of the drawn floor; the player starts standing on it, at -8.5), and off in
  the `"default"` and `"space"` themes, where the floor is only painted and you
  stand on platforms. `floorY` moves the landing plane only, not the drawn
  floor. For a ground at another height, or a bigger or coloured one, lay a
  platform (`h = 2` at `y = -1` puts its top at 0; `arena_3d` does).
* A player who falls below `deathPlaneY` dies (without a solid floor, or off
  the edge of a platform above the void); `world3dPlayerLethal` can catch that
  (the player then reappears at `world.spawnPos`). It is not damage:
  `world3dPlayerDamaged` does not fire for it.

### Entities

An entity is anything that lives in the world: an enemy, a target, a prop.

```lua
local e = world3d.spawn{
  tag = "chaser", x = 40, y = 4, z = 0,       -- tag: your own name for the kind
  hp = 30, radius = 4, shape = "cube", size = 7, color = "#e04848",
  ai = "chase", speed = 24, contactDamage = 8, scoreValue = 10, gravity = true,
  onSpawn = function(e) print("here", e.id) end,
}
```

`world3d.spawn{...}` takes any writable entity field, the shortcuts `x y z vx vy
vz`, and `model`, `ai`, `shape`, `size` (a number for a cube, or `{x=, y=, z=}`)
and `onSpawn`. It returns the entity straight away, but the entity joins the
world at the next [queue point](#lifecycle-and-timing): until then
`world3d.entities()` does not list it. An unknown key is an error naming it.
`hp` alone also sets `maxHp` (and the other way round). The profile's
difficulty scales an entity's HP once, when it joins. Defaults: `hp` 30,
`radius` 4, `shape` `"sphere"` (red), `size` 8, `ai` `"none"`, `speed` 30,
`orbitRadius` 60, `projectileSpeed` 150, `projectileDamage` 10.

| Field | |
|---|---|
| `id`, `alive`, `removed` | read-only. Ids are never reused within a world |
| `tag`, `hp`, `maxHp`, `radius` | `radius` is the hit and touch size. An entity brought to 0 hp dies |
| `pos`, `vel`, `yaw`, `x y z vx vy vz` | position, velocity, heading (degrees) |
| `shape`, `color`, `size` | `"none"`, `"cube"` (`size` = full extents), `"sphere"` (drawn from `radius`), `"cylinder"` (from `radius`; `size.y` is its height) or `"model"` |
| `model`, `modelScale`, `modelAnim`, `modelSpeed`, `modelFade` | a model from `assets.model` (or a file name); setting one makes the shape `"model"`. `modelScale` 0 fits the model to the entity's diameter; `modelAnim` is an animation number (1 is the first, 0 the rest pose); changing it crossfades over `modelFade` seconds (0.2; 0 switches at once) |
| `ai`, `speed`, `orbitRadius`, `range` | see below |
| `contactDamage`, `contactTimer` | damage when it touches the player, at most once a second |
| `fireInterval`, `fireTimer`, `projectileSpeed`, `projectileDamage` | shooting (an interval of 0 never shoots) |
| `scoreValue` | added to `world.score` when it dies with credit |
| `gravity`, `solid`, `invulnerable` | falls and lands on platforms; pushes the player out of its way; takes hits without losing hp |
| `age`, `wanderDir`, `wanderTimer` | bookkeeping |

**Built-in AI** (`ai`):

* `"chase"`: goes for the player at `speed` (straight at them, flying, when
  `gravity` is off);
* `"orbit"`: circles the player at `orbitRadius`;
* `"wander"`: strolls in random directions;
* `"turret"`: stands still, facing the player;
* `"none"`: nothing of its own (the default). Move it yourself.

Any AI shoots at the player while `fireInterval > 0` and the player is within
`range` (0 = any distance). Whatever the AI, physics always runs: `gravity`,
landing on platforms, the arena's walls and the death plane.

Methods: `e:damage(n)` returns the damage dealt (no damage number; an
`invulnerable` entity takes none), `e:kill([credit = true])` (runs
`world3dEntityDeath` and, with credit, counts the kill and its score),
`e:remove()` (gone at once, no hook, no score), `e:distanceTo(x, y, z)` or
`e:distanceTo(other)`, `e:valid()` and `e:fields()`. `world3d.entities([tag])`
lists the live, joined entities (of one tag).

### Projectiles and pickups

```lua
world3d.projectile{x = 0, y = 20, z = 0, vx = 0, vy = 0, vz = 100, damage = 8,
                   homing = true, lifetime = 4, tag = "seeker"}
world3d.pickup{x = 30, y = 3, z = 10, kind = "health", value = 25}
```

* **Projectile** keys: `x y z`, `vx vy vz`, `damage` (10), `fromPlayer`
  (false: it hurts the player; true: it hurts entities and the boss), `radius`
  (0 uses the default 1.5), `color`, `lifetime` (6 seconds), `homing` (a
  strength, or `true` for 200; enemy shots chase the player, the player's chase
  the nearest entity or the boss), `gravity` (a multiplier on the arena's; 0
  flies straight), `pierce` (extra targets it passes through), `tag` and
  `owner` (an entity). Its fields can be read and written afterwards, plus
  `active`, `ownerId` and `hitIds`. `p:remove()`, `p:valid()`, `p:fields()`.
* **Pickup** keys: `x y z`, `kind` (`"health"`), `value` (25), `radius` (4) and
  `color`. Touching one takes it: `"health"` heals `value`, `"ammo"` adds
  `value` shells, and **any other kind has no effect of its own**: catch it in
  `world3dPickup`. `k:remove()`, `k:valid()`, `k:fields()`.

Both are queued like entities. `world.projectiles` and `world.pickups` list the
live ones (`for p in world:pickups() do`).

### Other functions

* `world3d.damagePlayer(n [, source = "script"])` returns the damage taken: the
  `world3dPlayerDamaged` filter, the profile's difficulty and the invulnerable
  time all apply. `world3d.healPlayer(n)`.
* `world3d.shake(seconds)` trembles the camera for that long (0 to 5), strongest
  at the start and fading to nothing. It sets `camera.shakeTime`; a second call
  restarts the timer. The game's own boss fight never shakes.
* `world3d.boss()` is a read-only snapshot of the boss (`nil` without one);
  `world3d.damageBoss(n)` hurts its core directly and returns whether there was
  a boss to hurt. The boss's other fields (`world.boss.phase`,
  `satellites[i].health`, `pos`...) are writable, its health is not.
* `world3d.raycast(x, y, z, dx, dy, dz [, maxDist = 1000])` returns
  `{kind, dist, x, y, z, entity, platform}`. `kind` is `"none"`, `"floor"` (the solid floor), `"platform"`
  (with its `platform` number), `"entity"` (with the `entity`), `"boss"` or
  `"satellite"`; `x y z` is the hit point.
* `world3d.aim()` returns `x, y, z, dx, dy, dz`: the camera and where it points.
* `world3d.toScreen(x, y, z)` returns `screenX, screenY, visible`.
* `world3d.damageNumber(x, y, z, amount [, color])` floats a number.

### Drawing

* **In the world** (`world3dDraw`, and `world3dEntityDraw`): the `draw3d`
  library, in world coordinates, all shapes centred on x, y, z:
  `cube(x, y, z, w, h, d, color)`, `cubeWires`, `sphere(x, y, z, r, color)`,
  `sphereWires(x, y, z, r, color [, rings = 8, slices = 8])`,
  `cylinder(x, y, z, r, height, color [, slices = 16])`, `cylinderWires`,
  `line(x1, y1, z1, x2, y2, z2, color)`, `grid([slices = 10, spacing = 1, y = 0])`,
  `plane(x, y, z, w, d, color)`, `model(mdl, x, y, z [, options])` (the pose
  options of [3D models](#3d-models), plus `size`, the footprint in world
  units, 8 by default, or `scale`), `billboard(texture, x, y, z [, size = 8,
  tint])` (a sprite that always faces the camera, standing upright: `size`
  is its height, the width follows the picture),
  `texture(texture, x, y, z [, {w, h, yaw, pitch, roll, tint, frame, time}])`
  (see below) and
  `text(text, x, y, z [, size = 20, color, font])` (a label at a world point,
  size 10 to 120 in the game's font; a [font](#fonts) of your own goes last). `draw.*` there is an error (`draw.X is 2D: ... use the draw3d
  library`), and so is `draw3d.*` anywhere else.
* **Pictures fixed in the world:** `draw3d.texture` draws an image, a GIF or a
  [video](#videos) as a flat panel that keeps its place and turn, unlike a
  billboard: a screen, a sign, a poster, a decal. It is 8 tall unless given;
  give `w` or `h` alone and the other follows the picture's shape, give both
  to stretch it. Unturned it stands upright facing +z; `yaw`, `pitch` and
  `roll` (degrees) turn it like a model, so `yaw = 90` faces +x and
  `pitch = -90` lays it face up on the floor, its top toward -z. Both sides
  show it the right way round. `frame` / `time` pick a GIF's frame as in
  `draw.texture`, and `time` on the world's clock (`world.timeElapsed`)
  stops it while the world is paused. To face a point (px, pz):
  `yaw = math.deg(math.atan(px - x, pz - z))`. An unknown option is an error.
  Pictures and billboards are unlit.
* **See-through pictures:** fully see-through pixels (a GIF's background, a
  PNG's empty corners) are not drawn at all, so they hide nothing behind them.
  Half see-through ones (soft edges, a glow) still hide what is drawn after
  them and behind them: draw those last, farthest first, as the `media`
  example's plaza does with its orbs.
* **On the screen** (`world3dDrawHud(world, w, h)`): the ordinary `draw`
  library, in pixels over the view, after the built-in HUD.
* **Overriding the built-in looks:** `override.model(target, model)` and
  `override.texture(target, file)` take these 3D targets (`nil` clears; a
  texture is drawn as a billboard):

  | Target | Replaces |
  |---|---|
  | `"boss3d"`, `"satellite3d"` | the boss's core and its satellites |
  | `"entity3d:<tag>"` | every entity with that tag (an entity's own `model` wins) |
  | `"projectile3d:player"`, `"projectile3d:enemy"` | the two kinds of shot |
  | `"pickup3d:<kind>"` | a pickup kind, your own included |

* **HUD parts** (`hud.hide`): `"player"` (the HP / ammo box), `"boss"` (bar,
  phase, satellite count, banners), `"crosshair"` and `"damageNumbers"`, or
  `"all"`. Hide them from a mode's `onStart` or `world3dStart` and draw your own.

### Hooks

Registered with `hooks.on` like any other (the table is in [Hooks](#hooks)).
They fire for **every** world, so a mode checks `world.modeKey == MODE` and a
tweak for the boss fight checks `world.bossEnabled`.

```lua
hooks.on("world3dHit", function(damage, target, projectile)
  if target == "satellite" then return damage * 1.5 end   -- a filter
end)
hooks.on("world3dPickup", function(pickup)
  if pickup.kind == "overcharge" then return true end      -- taken, no built-in effect
end)
```

* `world3dHit(damage, target, projectile)`: `target` is an entity, or the
  string `"boss"` or `"satellite"`. Player shots only.
* `world3dPlayerDamaged(amount, source, entity)`: `source` is `"projectile"`
  (shots from entities and from the boss), `"contact"` (with the `entity`) or
  whatever `world3d.damagePlayer` was given (`"script"` by default). It is a
  filter: return a new amount, `0` cancels the hit.
* `world3dEntityDeath(e)` still lets you read the dead entity (position, tag,
  hp), to drop pickups or spawn more.
* `world3dEntityUpdate(e, dt)` returning `true` skips that entity's built-in AI
  for the frame (move it yourself); physics and contact damage still run.
  `world3dEntityDraw(e)` returning `true` skips its built-in body.
* `world3dShoot(world)` returning `true` replaces the shot (the weapon then
  waits its `fireRate` and uses no ammo); return nothing to just watch.
* `world3dBossPhase(phase)` and `world3dBossAttack(phase, pattern)` (`true`
  skips that attack) only fire in a boss fight.

### Lifecycle and timing

A frame of a world runs, in this order: `world3dStart` (the world's first
frame only, after `runStart` and the mode's `onStart`), `world3dPreUpdate`,
player movement and shooting (`world3dShoot`), the boss, the entities
(`world3dEntityUpdate`, contact hits, `world3dPlayerDamaged`), projectiles
(`world3dHit`), pickups (`world3dPickup`), removal of what died, then
`world3dUpdate`, and last the win / loss checks. `world3dEnd(world, result)`
fires when the world ends, with `"won"`, `"lost"` or `"exit"`. The ordinary
`runStart`, `preUpdate` and `update` hooks and `timer` callbacks keep running in
a world (and stop while it is paused).

* **Spawns are queued.** Hooks fire inside the game's loops, so `world3d.spawn`,
  `projectile` and `pickup` return an object at once but it joins the world
  after `world3dStart`, `world3dPreUpdate`, the entity stage and
  `world3dUpdate`. A thing you `remove()` before it joined never joins.
  Platforms and arena changes apply immediately.
* **Removal is a sweep.** A killed or removed entity, projectile or pickup
  leaves the lists at the end of the stage. Using a reference you kept is then
  an error (`entity no longer exists`), and so is anything from a finished
  world (`entity no longer exists (its 3D world has ended)`, `world no longer
  exists (the 3D world has ended)`); `e:valid()` just answers. Keep ids, not
  objects, across frames.
* **`finish` and `exit` land at the end of the frame**, so the rest of the
  frame still runs.
* **Errors** name the problem: `entity has no field 'x'`,
  `world.active is read-only`, `world.boss.health is read-only`,
  `world3d.spawn: 'id' cannot be set`, `world3d.arena.theme must be one of:
  default, space, empty`, `entity:kill() needs an entity (call it with ':')`.
  Numbers must be finite.
* **Limits.** A runaway loop must not eat the memory, so a world holds at most
  4000 entities, 20000 projectiles and 2000 pickups (a spawn past the cap is
  silently dropped, and so is a shot an entity fires), 300 floating damage
  numbers and 512 `draw3d.text` labels a frame; the weapon's `pellets` is
  clamped to 1 to 100 per shot.
* **What is not saved.** A world is never saved: its entities, projectiles,
  pickups, platforms and everything else vanish when the player quits. A 3D
  mode's run *does* checkpoint (Q at the pause screen), and Continue builds a
  fresh world with `resumed = true` in `world3dStart` and in the mode's
  `onStart`. Rebuild the arena there, and keep what must carry on in
  `run.data` (the wave, the score, the HP), as `arena_3d` does.
* The world3d hooks never run in PvP, which has hooks of its own (see [PvP](#pvp)).

## Shaders

GLSL fragment shaders can post-process the whole frame (desktop OpenGL 3.3,
`#version 330`; see `crt.fs` in the `cosmetics` example for the inputs raylib passes).

* `assets.shader("fx/crt.fs" [, "fx/crt.vs"])` returns a shader, with your own
  vertex shader if you give one (it must use raylib's input names:
  `vertexPosition`, `vertexTexCoord`, `vertexColor`, `mvp`). The game fills its
  `time` (seconds) and `resolution` (pixels) uniforms; `shader:set(name, value)`
  sets yours: a number, a list of 2 to 4 numbers, or a texture or video for a
  `sampler2D` (up to 4 of them; a GIF shows its current frame, a video its
  current picture). A shader that does not compile is an error with the reason.
* The frame reaches the shader upside down, so `fragTexCoord` runs from the
  bottom of the screen: sample your own texture at
  `vec2(fragTexCoord.x, 1.0 - fragTexCoord.y)` to keep it upright.
* `override.shader("game", shader)` runs it over every frame while a run is on
  screen; `override.shader("screen", shader)` over everything, desktop
  included. Pass `nil` to switch it off.

## The HUD

`hud.hide(part)` hides a piece of the built-in HUD so you can draw your own in
`drawHud`; `hud.show(part)` brings it back and `hud.hidden(part)` asks. Parts:
`"all"`, `"player"` (health, power-ups), `"run"` (the wave / survival /
sector panel), `"boss"`, `"combo"`, `"banners"`, `"abilities"`, `"hints"`,
`"vignettes"`, `"docks"` (the widescreen side panels' background),
`"damageNumbers"`, `"crosshair"` (3D worlds only; `"player"`, `"boss"`
and `"damageNumbers"` also apply there) and `"restorePoints"` (the
[restore-point](#restore-points) meters on the crash, pause and victory screens,
and the animation when one is spent; `"all"` leaves them). Every run starts with the full HUD, so hide parts from
`runStart` (or a game mode's `onStart`).

## Apps

`register.app` adds a program to the desktop: settings for your mod, an info
page, a toy. Each app is a real window (title bar, drag, minimize, close, focus
like the game's own) with an icon on the desktop that opens it; **MODS.EXE >
Apps** lists every app with an Open button too. The app draws in the window's
canvas, in canvas coordinates.

```lua
register.app{
  id = "settings", name = {en = "My Settings", es = "Mis Ajustes"},
  icon = assets.model("ship.glb"), color = "#7de2ff", width = 420, height = 260,
  draw = function(w, h, mouseX, mouseY) draw.text("Hello", 20, 20, 20, "#ffffff") end,
  update = function(dt) end,                      -- every frame while open
  click = function(x, y, button, w, h) end,       -- a click inside the canvas
  drag = function(x, y, w, h) end,                -- while the left mouse button is held
}
```

| Option | Meaning |
|---|---|
| `id` | required, unique in your mod (the app is `<mod id>:<id>`) |
| `name` | text or `{en = ..., es = ...}`: the window title and the icon label |
| `draw` | required, `draw(w, h, mouseX, mouseY)`: the canvas size and the mouse in canvas coordinates (-1, -1 when it is outside the canvas or another window covers it) |
| `update` | optional, `update(dt)`: runs every frame the window is open and not minimized (not while it is closed or minimized) |
| `click` | optional, `click(x, y, button, w, h)`: a click inside the canvas (`"left"` or `"right"`), only when this window is the one under the pointer |
| `drag` | optional, `drag(x, y, w, h)`: called while the left mouse button is held after a click in this app's canvas |
| `icon` | optional: a texture or model (`assets.texture(...)` / `assets.model(...)`, or a file name: an image or video is a texture, anything else a model) shown in the desktop icon. Without one the icon shows a small window with the app's initial. A model icon also reads the pose options of `override.model` (`tilt`, `spin`, `animation`...) from the same table |
| `color` | optional accent for the window and the icon tile (default: MODS.EXE green) |
| `width`, `height` | optional canvas size in pixels (default 480 x 360; 240-960 wide, 160-640 tall) |
| `resizable` | optional, default `false`. When `true` the player can drag the window's edge: `draw` and `click` then get the current canvas size, so lay out from `w` and `h`. Resizable windows open at least 400 x 300 |
| `desktop` | optional, default `true`. `false` puts no icon on the desktop; the app is still reachable from MODS.EXE > Apps |

The desktop icons of mod apps sit in columns of their own after the game's
icons, in the order the apps were registered, tagged MOD. Opening an app that is
already open just brings its window to the front. Keep settings in
`mod.storage` so they survive restarts (see `cosmetics`).

## Interface themes

The desktop, its windows, dialogs and notifications are drawn in an
**interface theme**: TopHat-ShooterOS (the stock look), CKN OS (unlocked by the
last story recording) or one a mod registers. The player picks it in
**SETTINGS.sys > Interface > Theme**; the shop's SECRET tab also equips CKN
OS. A run's own screens (the HUD, the pause menu, the crash screen) and the
story cinematics always keep the stock look.

```lua
register.theme{
  id = "midnight", name = {en = "Midnight", es = "Medianoche"},
  base = "ckn",                 -- the hand-drawn pieces: "tophat" or "ckn"
  surface = "#14182a",          -- window bodies and panels
  raised = "#2b3350",           -- buttons, tabs, cards
  text = "#eef2ff",             -- text
  muted = "#8b93ad",            -- secondary text
  accent = "#ff5fd2",           -- focus, selection, highlights
  wallpaper = "art/night.png",  -- optional
}
```

| Option | Meaning |
|---|---|
| `id` | required, unique in your mod (the theme is `<mod id>:<id>`, which register.theme returns) |
| `name` | text or `{en = ..., es = ...}`: what Settings shows |
| `base` | optional, default `"tophat"`. The theme's shell, the pieces drawn by hand: `"tophat"` has glowing square frames, the OS Grid wallpaper and the crosshair pointer; `"ckn"` has rounded frames with soft shadows, the CKN Dawn wallpaper, a Start button with CKN's logo and an arrow pointer. Either draws in your colours |
| `surface`, `raised`, `text`, `muted`, `accent` | optional colours (`"#rrggbb"` or a table); each one left out is the base theme's |
| `wallpaper` | optional texture (or file name): the free default wallpaper while the theme is on. A wallpaper the player equipped (shop or MODS.EXE) still wins |

Every colour the game's interface draws plays a role, and your five colours
anchor them, so you do not restyle windows one by one. A fill (a window's
body, a panel, a button) lands between `surface` and `raised` by how raised it
is on the stock theme; text lands between `muted` and `text`; the stock cyan
accent becomes your `accent`. Every other hue keeps its meaning (red still
reads as danger, green as done, gold as currency) at a lightness that reads on
your surfaces, so a light `surface` makes a light theme. Pictures are never
recoloured: skins, icons, wallpapers, previews and your own textures keep
their colours in every theme. Themes register while the mod loads (like the
other `register.*`), and a content pack can hold them too.

The `theme` library:

* `theme.current()` is the id of the theme the interface is drawn in, and
  `theme.list()` the ids the player can pick right now (built-ins first, then
  loaded mods' themes; CKN OS only once it is unlocked).
* `theme.set(id)` makes `id` the player's theme and saves it, as if they
  picked it in Settings. Your own themes work without the `"<mod id>:"`
  prefix. It returns `false` for an unknown or still-locked theme. It changes
  the player's choice, so call it from something they did (an app's button),
  not every time the mod loads.
* `theme.colors([id])` is a table of the theme in use (or of `id`): `id`,
  `name`, `base`, `light` (a light theme) and its five colours.
* `theme.surface(color)`, `theme.line(color)`, `theme.ink(color)` and
  `theme.glow(color)` hand back the colour the game's own interface would draw
  for `color` in the theme in use, in each role (a fill; a border; text; a
  translucent highlight). Pass the colour you would use on the stock dark
  theme. An app's canvas, and everything a mod draws, keep the colours given,
  so an app that should follow the player's theme picks them through these:

```lua
draw = function(w, h)
  draw.rect(0, 0, w, h, theme.surface("#0c0e14"))
  draw.text("Hello", 20, 20, 20, theme.ink("#ffffff"))
end
```

## Mod keybinds

Mods can register their own keyboard and gamepad actions. The action ID is
automatically namespaced by the owning mod, so two mods may use the same local
ID. Keys are allowed to overlap: both actions report input when their key is
held. The optional `name` table supplies English and Spanish labels for the
mod keybind subsection in Settings > Controls.

```lua
local reload = register.keybind{
  id = "reload",
  name = {en = "Reload", es = "Recargar"},
  default = "r",
  gamepad = "RightFaceDown"
}

hooks.on("update", function(game, dt)
  if input.bindPressed("reload") then
    -- reload the mod's weapon
  end
end)
```

Use `input.bind(id)`, `input.bindPressed(id)` or `input.bindReleased(id)` for
the registered action. Bindings changed by the player in Settings > Controls
(the mod keybind subsection) are
stored per profile and restored when that mod is loaded again. A failed or
disabled mod contributes no keybinds, and bindings are only visible while the
owning mod is loaded. `default` is a raylib keyboard key name; `gamepad` is an
optional raylib `GamepadButton` name and defaults to unbound.

## Timers, input, drawing, text

* `timer.after(seconds, fn)`, `timer.every(seconds, fn)` return an id for
  `timer.cancel(id)`. They run on game time and are cleared when a run starts.
  (Coroutines work too, but they only move when you resume them: to spread
  work over frames, resume one from an `update` hook.)
* `input.down(key)`, `input.pressed(key)`, `input.released(key)` with names
  like `"space"`, `"e"`, `"f1"`, `"leftShift"`, `"1"`;
  `input.action("dash")` checks the player's own key binding;
  `input.mouse()` returns arena x, y; `input.screenMouse()` returns screen x, y;
  `input.mouseDown("left")`, `input.mousePressed("right")`.
* Drawing works inside draw hooks only: `draw.circle(x, y, r, color)`,
  `draw.circleLines(x, y, r, color [, thickness])`,
  `draw.rect(x, y, w, h, color)`, `draw.rectLines(x, y, w, h, color [, thickness])`,
  `draw.line(x1, y1, x2, y2, color [, thickness])`,
  `draw.poly(x, y, sides, radius, rotationDegrees, color)`,
  `draw.text(text, x, y, size, color [, font])` (returns the width),
  `draw.textWidth(text, size [, font])`, and `draw.arena()`, which returns x, y, w, h
  of the arena (in `drawHud`, where it sits on screen: the widescreen side
  panels are outside it). Text in the game's own font is at least size 10; for
  your own, see [Fonts](#fonts).
* Colours: `{r = 255, g = 128, b = 0, a = 255}`, `{255, 128, 0}`, or
  `"#ff8000"` / `"#ff8000cc"`. `color.rgb(r, g, b [, a])` and `color.hex(s)`
  build the table form.
* `lang.text(key)` reads any game string; `lang.current()` is `"en"` or
  `"es"`; `lang.set("en", key, text)` and
  `lang.add({en = {key = "Text"}, es = {key = "Texto"}})` add strings or
  replace the game's own.

## Your mod, the run, other mods

* **Register while loading.** Every `register.*` call (and `roster.add`)
  works only while your mod loads, in its main chunk (or a file it
  `require`s from there): mods register in load order, so the same set of
  mods always gets the same slots. Calling one from a hook, a timer or an app
  is an error. `override.*` and `lang.*` work at any time.
* Each mod has its own copy of every library table (`draw`, `spawn`, `hooks`,
  `math`...): replacing `draw.circle` in yours changes nothing for other mods.

* `mod.id`, `mod.name`, `mod.version`, `mod.author`; `mod.log(...)` and
  `mod.warn(...)` write to the Log tab (so does `print`).
* `run.data` is a table saved with the run: plain numbers, strings, booleans
  and tables survive quitting and resuming (functions do not). You may also
  replace it whole (`run.data = {...}`). `run.active` is true while a run is
  on screen.
* `run.resumable` says whether quitting saves this run to be resumed (the
  mode's `resumable`, true for the game's own modes). Set it to `false` and
  quitting ends the run instead, and a save already on disk goes at once;
  `true` allows it again. It lasts for this run only, in any mode.
* `run.restorePoints`: the run's restore points (see
  [Restore points](#restore-points)).
* `mod.storage` is a table kept between sessions, per profile (your mod's own
  settings, records or unlocks). It is saved when mods reload and when the game
  closes; `mod.saveStorage()` saves it right away. Same plain-data rule.
* `mod.dir`, `mod.path(rel)` and `mod.dataDir()`: your folder, an absolute
  path, and a folder of yours in the profile to write files into (see
  [The language](#the-language)).
* `mods.export(value)` publishes an API; another mod reads it with
  `mods.get("your_id")` (list yours in its `dependencies` so you load first),
  or requires its modules directly with `require("your_id:module")`.
  `mods.isLoaded(id)`, `mods.list()` and `mods.dir(id)` tell what else is
  running and where it lives.

## The examples

The example mods are in MODS.EXE's **Marketplace**, like every published mod:
the game ships none of its own. Their source is the `examples/` folder of the
[mod registry](https://github.com/Paycei/TopHat-Shooter-ModRoot/tree/main/examples).
Updating one through the Marketplace replaces its folder, so keep your own
changes in a renamed copy:

| Example | Shows |
|---|---|
| `hello_hud` | the basics: hooks, drawing in the arena and on the HUD, run.data and a mod keybind (`disableAchievements: false`) |
| `house_rules` | a new game mode that rewrites rules: dash, pickups, the shop, level-ups and its own HUD panel |
| `story_mode` | a story told in a mode: a cutscene, dialogue with a portrait, a blessing chosen with `ui.choose`, a choice that changes the run through filters, a HUD card and a pause-menu action |
| `overclock` | new content for wave mode: an enemy with its own movement and look, a power-up with levels, and a boss with scripted attacks and movement that replaces a wave boss |
| `necromancer` | a status of its own (Soul Burn), allies as things (thralls raised from burning enemies), per-enemy data, and mod events and `mods.export` for other mods to build on |
| `chaos_engine` | telegraphed hazards, the camera and time on boss fights, a shop item, a roguelite patch, a survival event, vetoes and filters on Time Survival, a mod achievement and a Help-terminal command |
| `content_pack` | a mod without a script: power-ups, an enemy in wave mode's roster, a shop item and a consumable from JSON files under `content/` |
| `cosmetics` | looks only: player skins (a palette, an animated GIF, a 3D model), bullets (a palette, a 3D model), a wallpaper, a voxel desktop cube, a CRT post-processing shader, and a desktop app (with a 3D icon) that tunes the shader and swaps an enemy for an animated model, kept in `mod.storage` (`disableAchievements: false`) |
| `media` | videos and music in two files joined with `require`: a desktop app with a seek bar, a music track that takes over the game's music, a playlist read with `assets.json`, an LCD font and a video as its desktop icon; and Billboard Plaza, a 3D mode with pictures fixed in the world (`draw3d.texture`: a video with sound that gets louder as you walk up, a PNG, a GIF, a turning video, a floor decal), sprites that face you (`draw3d.billboard`, see-through ones drawn farthest first), entities drawn as a GIF, a screen you shoot to pause (`world3d.raycast`), videos held while the world is paused, and no resuming or restore points (`resumable = false`, `restorePoints = false`; `disableAchievements: false`) |
| `arena_3d` | 3D worlds, both ways: Cube Siege, a complete 3D game mode (waves of entities with built-in AI, pickups, a shotgun tune, a custom HUD, `draw3d` and a `run.data` to continue from), and changes to the game's own 3D boss fight (extra drones, a phase message and a hit filter) |
| `mixins` | the open side: wraps the game's damage and power-up offer procs (`mixin.wrap`, `mixin.after`), calls a game proc (`engine.player.heal`), draws a minimap into a raylib render texture in the `frame` hook, keeps a file in `mod.dataDir()` with `io`, loads a module of its own with `require`, and opens a screen of its own with F7 (`register.screen`) |
| `critical_section` | a PvP mode, Critical Section (king of the hill): lobby presets, scores and a moving zone in `match.data`, privileged rounds through `pvpShoot` and `match:spawnBullet` drawn by `pvpBulletDraw`, a blink on a mod keybind sent with `match:request` and shown everywhere with `match:broadcast`, the end decided by `pvpEnding` and `match:finish`, and its own HUD (`disableAchievements: false`) |

## PvP

Mods can change PvP matches too: new rules and objectives, weapons, abilities,
a HUD of their own, whole modes. The `critical_section` example is a complete
one: king of the hill, with privileged rounds and a blink.

### Who runs what

Everyone in a PvP lobby runs the same mods: the host refuses a player whose
loaded mods (ids, versions and every file) differ from its own. So every
machine runs your script, but **only the host decides the match**: it moves the
bullets, lands the hits, counts the kills and ends the match, and the clients
are sent the result. Two kinds of hooks follow from that:

* **Host hooks** change the match and fire on the host only: `pvpUpdate`,
  `pvpShoot`, `pvpBulletUpdate`, `pvpBulletHit`, `pvpPlayerDamaged`,
  `pvpPlayerLethal`, `pvpSpawnPoint`, `pvpPickup`, `pvpPackage`,
  `pvpPlaceWall`, `pvpEnding` and `pvpRequest`.
* **Every-machine hooks** draw and react, on the host and on each client:
  `pvpStart`, `pvpEnd`, `pvpFrame`, the draw hooks, `pvpKill`, `pvpRespawn`
  and `pvpBroadcast`. `match.isHost` tells the machines apart where it matters.

What the host changes reaches every client by itself:

* **The players**: position, HP and max HP, speed, damage, fire rate, bullet
  speed, size (`radius`), walls, kills, team and the package buffs. Setting a
  player's `x` / `y` on the host (or `match:teleport`) is a teleport: every
  machine snaps the player there.
* **The bullets**, with their size, damage, lifetime, colour, `kind` and `pierce`.
* **`match.data`**, your mod's table for the match (below).

Anything else a script changes stays on the machine that changed it: a client
that sets `player.speed` only fights the host's next correction. The run side
of the API does not exist in a match, which is not a run: no run hooks
(`update`, `enemySpawn`, `shoot`...), no `game`, `player` or `run.data`, no
`spawn.*`, things, statuses, camera or time. Mod cosmetics, textures, models,
sounds, text and `"screen"` shaders all work, and every player sees everyone's
mod ship and bullets.

### PvP modes

```lua
local MODE = register.pvpmode{
  id = "hill",
  name = {en = "King of the Hill", es = "Rey de la Colina"},
  description = {en = "Hold the hill to score.", es = "Ocupa la colina para puntuar."},
  settings = {killLimit = false, timeLimit = 240, respawn = 2},
  onStart = function(match) end,   -- every machine, right after pvpStart
}
```

The host picks a mode in PVP.EXE's **Mode** row when hosting (the game's own
rules are **Standard**); its name and description show over the countdown on
every machine. Hooks fire in every match, so a mode's rules check
`match:isMode(MODE)` (`match.mode` holds the key, `""` in a Standard match).

`settings` are presets: picking the mode puts them into the lobby, and the
host can still change them. They use the lobby's names and ranges: `hp`,
`speed`, `damage`, `fireRate` (seconds between shots), `bulletSpeed`,
`bulletSize`, `walls`, `killLimit`, `respawn` (seconds), `timeLimit`
(seconds), `packages` (true / false) and `teams` (false, true, or 2 to 6
teams). `killLimit`, `timeLimit`, `respawn` and `walls` take `false` (or 0)
for off: with `killLimit = false` no number of kills ends the match, only the
clock or your script does (the lobby shows it as OFF; only a mode can set it).
Picking another mode puts the old one's presets back to the game's values. An
unknown setting is an error that lists the names.

### The match

Every pvp hook gets the match. `match` is also a global, like `game` in a run.

| Field | |
|---|---|
| `isHost` | this machine runs the match |
| `mode` | the mode's key, `""` in a Standard match |
| `localPlayer` | this machine's player |
| `time`, `timeLeft` | seconds on the match clock, and left (`math.huge` with no time limit) |
| `live`, `countdown`, `over` | playing, counting down, finished |
| `teams`, `playerCount`, `width`, `height` | a team match; the player slots; the arena (1024 x 768) |
| `settings` | a copy of the rules, by the names above (`hp`, `killLimit`, `teams`...) |
| `data` | your mod's table for this match (below); the only field you can set |

Players are the usual player objects (`p.hp`, `p.x`, `p.speed`, `p.kills`,
`p.teamId`, `p:fields()`...) plus, in PvP, `p.index` (the slot, 1 to
`playerCount`: the P1, P2... on screen), `p.name`, `p.deaths`, `p.streak`,
`p.alive`, `p.connected` and `p.isLocal`, all read-only. Bullets add `b.owner`
(the player who fired, or nil), `b.kind` and `b.pierce`.

On every machine:

* `match:players()` iterates the players still connected, alive or not:
  `for p in match:players() do ... end`. `match:player(i)` gets one by slot.
* `match:nearestPlayer(x, y [, maxDist [, except]])` returns the closest
  living player.
* `match:isMode(key)`, `match:fields()`.
* `match:request(name [, data])` asks the host for something (below).
* `match:toast(text [, color])`, `match:banner(text [, sub [, color]])` and
  `match:particles(x, y [, color [, count]])` show something **on this machine
  only** (text is `"Text"` or `{en = .., es = ..}`; broadcast to show it on
  all of them).

On the host only (a client gets an error: `match:spawnBullet() changes the
match, which only the host does`):

* `match:spawnBullet{x, y, vx, vy, owner, damage, radius, lifetime, color,
  kind, pierce}` returns the new bullet. A bullet with an `owner` (a player)
  never hits its owner or their teammates and counts in their accuracy; one
  without hits everyone. `x` and `y` default to the owner's position,
  `damage` to the owner's, `radius` to the match's bullet size, `lifetime` to 5
  seconds. `kind` is any name you give your bullets, to draw or treat them
  differently; `pierce` is how many players it goes through (each one once).
  Like spawns in a run it joins at the next step of the frame, and every
  machine sees it. An arena holds at most 512 bullets.
* `match:removeBullet(bullet)`.
* `match:damage(player, amount [, attacker])` hits like a bullet does:
  FIREWALL.SYS blocks it, `pvpPlayerDamaged` sees it, and a kill counts for
  `attacker`. `match:kill(player [, killer])` downs a player at once;
  `match:heal(player, amount)` heals up to max HP.
* `match:teleport(player, x, y)`: every machine snaps the player there.
* `match:finish([winner [, reason]])` ends the match now. `winner` is a
  player, a team (`"red"` or `"ptRed"`) or nil for a draw; `reason` (`"Text"` or
  `{en = .., es = ..}`) is the line under the result, in each player's language.
* `match:broadcast(name [, data])` (below).

### match.data

`match.data` is your mod's table for the match. The host's copy goes to every
machine, so put there what the clients need to draw: a zone, the scores,
cooldowns. It starts empty at each match (rematches too), goes out with the
start signal (so it is there for the countdown), with the snapshots during
play and with the result.

* Plain data only (numbers, strings, booleans, tables), like `run.data`, up to
  16 KB of it as JSON per mod.
* On a client it is a copy, refilled with the host's whenever that changes.
  Keep what a client works out for itself in your own variables.
* The host's changes reach the clients within a snapshot (32 a second at the
  lobby's default net quality).

### Requests and broadcasts

A player's machine asks the host for something with
`match:request(name, data)`: the host's `pvpRequest(match, player, name, data)`
hook gets it, as that player. The host tells everyone something with
`match:broadcast(name, data)`: every machine's `pvpBroadcast(match, name, data)`
gets it, the host's own included. That is how a key one player presses
becomes something the host does and everyone sees:

```lua
hooks.on("pvpFrame", function(match)                  -- every machine: its own player
  if input.bindPressed("blink") then
    local x, y = input.mouse()
    match:request("my_mod:blink", {x = x, y = y})
  end
end)

hooks.on("pvpRequest", function(match, p, name, data) -- the host
  if name ~= "my_mod:blink" or type(data) ~= "table" then return end
  match:teleport(p, data.x, data.y)
  match:broadcast("my_mod:flash", {x = data.x, y = data.y})
end)

hooks.on("pvpBroadcast", function(match, name, data)  -- every machine
  if name == "my_mod:flash" then match:particles(data.x, data.y, "#64d8ff") end
end)
```

* The host's own player uses the same path: `match:request` on the host goes
  straight to its `pvpRequest`.
* They arrive in order and exactly once, even over a connection that drops
  packets (each is re-sent until the other side has it), but only during play:
  what is sent during the countdown or on the result screen goes out when play
  starts, and a rematch drops whatever is left of the last match.
* A name is 1 to 64 characters (start it with your mod id); the data is plain
  data, up to 8 KB of it as JSON.
* A request is another machine's word: check its data before you act on it.

### PvP hooks

| Hook | Arguments | Runs on | Kind |
|---|---|---|---|
| `pvpStart` | match | every machine | event: a match (or rematch) is about to count down, with an empty `match.data`. The host places the players right after it (see `pvpSpawnPoint`) |
| `pvpEnd` | match, winner | every machine | event: the match ended; `winner` is the player, the team's name or nil |
| `pvpFrame` | match, dt | every machine | event: every frame of play, after the step (read your player's input here) |
| `pvpUpdate` | match, dt | host | event: every frame of play, before the snapshot goes out |
| `pvpDrawBackground` | match | every machine | draw in arena coordinates, on the floor under everything |
| `pvpDrawWorld` | match | every machine | draw in arena coordinates, over everything |
| `pvpDrawHud` | match, w, h | every machine | draw in screen coordinates, under the scoreboard, the countdown and the result |
| `pvpPlayerDraw` | player, match | every machine | cancel: true skips the built-in body; `"all"` also skips its team ring, name and health bar |
| `pvpBulletDraw` | bullet, match | every machine | cancel: true skips the built-in look |
| `pvpShoot` | match, player, dirX, dirY, aimX, aimY | host | cancel: true replaces the shot (spawn your own) |
| `pvpBulletUpdate` | bullet, dt, match | host | cancel: true skips the built-in movement (its lifetime still runs out) |
| `pvpBulletHit` | damage, bullet, victim, match | host | filter: the damage; `false` lets the bullet fly on through |
| `pvpPlayerDamaged` | amount, victim, attacker, match | host | filter: damage about to land (after FIREWALL.SYS), from bullets and `match:damage`; `attacker` may be nil |
| `pvpPlayerLethal` | victim, attacker, match | host | cancel: true keeps the victim alive (set its `hp`, or it is left on 0.5) |
| `pvpKill` | match, victim, killer | every machine | event (`killer` may be nil) |
| `pvpRespawn` | match, player | every machine | event |
| `pvpSpawnPoint` | match, player, x, y | host | return x, y to start or respawn the player somewhere else |
| `pvpPickup` | match, player, kind | host | cancel: true takes the package without its effect (`kind`: `"pkChkdsk"`, `"pkFirewall"`, `"pkTurbo"`, `"pkOverclock"`, `"pkFork"`) |
| `pvpPackage` | kind, match, power | host | filter: the package a port drops next (return another kind's name); `power` is the centre port |
| `pvpPlaceWall` | match, player, x, y | host | cancel: true places no wall |
| `pvpEnding` | match, reason | host | cancel: the rules are about to end the match (`"kills"`, `"time"` or `"elimination"`); true keeps it going. `"time"` is asked every frame until the match ends: call `match:finish` from it to name the winner yourself |
| `pvpRequest` | match, player, name, data | host | a player's `match:request` |
| `pvpBroadcast` | match, name, data | every machine | the host's `match:broadcast` |

* A frame of a match runs: the network, then requests and broadcasts, then
  this machine's own input (`pvpShoot` on the host). On the host: respawns
  (`pvpSpawnPoint`, `pvpRespawn`), the other players' input, the time limit
  (`pvpEnding`), the bullets (`pvpBulletUpdate`, `pvpBulletHit`, damage,
  `pvpKill`), the packages, `pvpUpdate` and the snapshot. Last, on every
  machine, timers and `pvpFrame`.
* `timer.after` and `timer.every` run on the match clock during play, on the
  machine that set them, and are cleared at each match.
* `hud.hide` works in PvP for `"all"` (the whole match HUD: scores, clock,
  ping, feed, walls and buffs), `"banners"` (callouts and package toasts),
  `"vignettes"` and `"damageNumbers"`. Each match starts with everything shown.
* `input.*` and mod keybinds work as in a run; `input.mouse()` is the arena
  point under the cursor.
* A script error on one machine stays there (the error is logged and that
  call does nothing); the host's rules keep running everyone's match.
* To test alone, start the game twice on one computer: host in one, and join
  `127.0.0.1` from the other.

## Publishing your mod

Mods reach players through **MODS.EXE's Marketplace**. It lists the mods of the
official registry,
[github.com/Paycei/TopHat-Shooter-ModRoot](https://github.com/Paycei/TopHat-Shooter-ModRoot).
A mod stays in its own GitHub repository. The registry holds one file per mod,
which points to that repository at a fixed commit: the one a maintainer
reviewed.

1. **Put the mod in a public GitHub repository.** `mod.json` goes at the root,
   or in a subfolder (see `path` below). Set `version` in `mod.json`.
2. **Push the commit to publish** to the repository's default branch and copy
   its full id (`git rev-parse HEAD`).
3. **Fork the registry and add `mods/<id>.json`**, named after your mod's `id`:

   ```json
   {
     "id": "hello_hats",
     "title": "Hello Hats",
     "description": "Every enemy wears a tiny top hat. Purely cosmetic: rewards stay on.",
     "repo": "https://github.com/your-name/hello-hats",
     "commit": "4f1c2e8d0b6a5c3e9f7a1b2c4d6e8f0a1b3c5d7e",
     "version": "1.0.0"
   }
   ```

4. **Open a pull request.** Its check downloads your mod at that commit and
   compares it with the entry. A maintainer then reviews the code and merges it.

The fields:
- **`title`** (1-48 characters) and **`description`** (one line, 1-240) are what
  the Marketplace shows. They must use characters the game's font draws
  (Latin-1: accents yes, emoji no).
- **`commit`** is the full 40-character id, and it must be on the default branch.
- **`version`** must equal the one in `mod.json` at that commit.
- **`path`** (optional) is the folder that holds `mod.json`, when that is not
  the repository's root.

The author shown is the repository's owner.

**Updating.** Push the new version (raise `version`), then open a pull request
that changes `commit` and `version` in your entry. Players who installed the mod
see it tagged UPDATE.

**What players get.** The game downloads GitHub's archive of your repository at
that commit. It checks that the archive is that commit and that its `mod.json`
has the entry's `id`, then installs the folder holding `mod.json` into
`<game data>/mods/<id>/`, byte for byte.
- Keep the repository small, because the whole archive is downloaded.
  `export-ignore` in a `.gitattributes` keeps files out of it, for example
  `screenshots/ export-ignore`.
- Git LFS files are not in GitHub's archives.
- Files your `.gitignore` ignores are not in it either: GitHub's Lua template
  ignores `*.obj`, which hides OBJ models (un-ignore them with `!*.obj`).
- Symbolic links are skipped.

**Trying your entry first.**
- Clone the registry, add your entry, and start the game with
  `--mod-registry <the clone's folder>`. The Marketplace then lists your copy of
  the registry and installs from GitHub as usual.
- The registry's `python tools/validate_registry.py --online mods/<id>.json`
  runs the pull request's check on your machine.

A mod from the Marketplace is a mod folder like any other: tick it and press
Apply & Reload. The Installed tab tags it MARKETPLACE. If you already have a
copy of that mod that you made yourself, installing asks first, then replaces
your copy. An update of a loaded mod is swapped in when the mods reload.
