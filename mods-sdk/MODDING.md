# TopHat-ShooterOS modding guide

Mods change how the game plays: new rules, new enemies, bosses and power-ups,
new game modes, new looks. They are small programs written in **Lua 5.5**
(the real thing, built into the game), run in a sandbox.

A mod can reach almost everything: every field of the game state (down to
nested lists and objects), replace the game's own behaviour at dozens of
points (movement, dash, shooting, bullets, pickups, the shop, level-ups,
enemy AI, boss attacks...), hide the HUD and draw its own, build first-person 3D worlds, dress the game in
textures and 3D models, post-process the screen with shaders, and add its
own apps to the desktop.

> **Modded runs count as cheated.** Any run started while at least one mod is
> loaded earns no Data Shards, statistics, advancements or unlocks. The one
> exception: a run keeps its rewards when *every* loaded mod sets
> `"disableAchievements": false` in its `mod.json` (see below), which is meant
> for mods that don't change how a run plays. Otherwise unload
> every mod (MODS.EXE, untick, Apply & Reload) to play for keeps again.

## Getting started

1. Open **MODS.EXE** on the desktop and press **Install Examples**. That writes
   this guide and a few example mods into your mods folder.
2. Tick a mod, press **Apply & Reload**, start a run.
3. Press **Open Folder**, copy an example folder, rename it, change the `id` in
   its `mod.json`, and start editing. Apply & Reload picks up your changes; the
   **Log** tab shows `print` output and every error with its file and line.

Mods live in `<game data>/mods/<folder>/` (the folder Open Folder shows) or,
for portable installs, in a `mods` folder next to the game executable.

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
  "disableAchievements": true
}
```

* `id`: 1-40 characters, lowercase letters, digits and `_`. It must be unique.
* `main`: the script run when the mod loads (default `main.lua`).
* `dependencies`: mods that must be enabled and load first. If one is missing
  or fails, this mod is skipped.
* `loadAfter`: mods that load first *if* they are enabled.
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

The libraries are `string`, `table`, `math`, `utf8`, `coroutine` and the base
functions (`print` writes to the Log tab). Left out, because a mod must not
reach your computer: `io`, `os`, `package`, `debug`, `load`, `loadfile` and
`dofile`; `collectgarbage` only takes `"count"`, `"collect"` and `"step"`.

A few extras: `math.clamp(x, lo, hi)`, `math.lerp(a, b, t)`, `math.sign(x)`,
`math.round(x)`, `string.split(s [, sep])`, `string.trim(s)`, and the Lua 5.1
names `unpack`, `math.pow` and `math.atan2` for older code.

`require("folder.file")` runs `folder/file.lua` from your own mod folder once
and returns what it returned.

Each mod has its own globals: two mods can both define `update` or change
`math` without touching each other.

Lua 5.5 prints whole floats with a decimal point (`10 / 2` is `5.0`); use
`//`, `math.floor` or `math.round` for whole numbers, or `%d` in
`string.format`.

### Safety rails

* A script that runs too long (an endless loop) is stopped with an error
  rather than freezing the game. `pcall`, `xpcall` and coroutines cannot
  catch that error.
* All mods together may use up to 256 MB; going over is an error in whatever
  script is running.
* A mod that keeps erroring, or keeps taking more than 8 ms of a frame, is
  switched off for the session with a notice. The game carries on.
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

Enemy types are named like the game's own (`"etCircle"`, `"etCube"`,
`"etThread"`, `"etFragment"`...); `enemies.types()` lists them all.

## The game, the player, enemies and bullets

`game` and `player` are always available during a run (they are also passed
to most hooks). Enemies and bullets come from hooks and iterators.

**Every field can be read by name, and almost all can be written**, all the
way down: numbers, flags, text and enums, but also nested objects and lists.

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
  table of its fields, and a list from a list (element by element).
* Lists keep their length: add and remove things with the API (`spawn.*`,
  `e:remove()`, `player:give`...), not by writing past the end.
* Nested objects and list entries are live views, not copies: keep one in a
  variable and it follows the game. If what it pointed at is gone (a list
  shrank), using it is an error that says so.
* Read-only: `game.mode`, `game.state` and the modding bookkeeping fields;
  `player.baselineMaxHp`; an enemy's `id`, `enemyType`, `isBoss`,
  `bossDefinitionID`, `currentPhaseIndex`, and a boss's `hp`/`maxHp`;
  everything under `game.rogueliteProfile` (it is your real progression).
* Writing nonsense (a negative size, an index past a list's end in a field the
  game uses as one) can break the run or crash the game: the game trusts its
  own numbers. Modded runs never touch your real saves, but be careful.

Methods:

* `game.enemies` and `game.bullets` are the live lists (`#game.enemies`,
  `game.enemies[1]`); calling one iterates it, skipping dead enemies:
  `for e in game:enemies() do`.
* `game:enemyCount()`, `game:nearestEnemy(x, y [, maxDist])`,
  `game:enemiesNear(x, y, radius)`, `game:isMode("wave")` (also `"survival"`,
  `"roguelite"`, `"sandbox"` or a mod game mode id).
* `player:powerUpLevel("puDoubleShot")`, `player:hasPowerUp(name)`.
* `enemy:valid()`: still alive and still in the run.

## Changing the game

**Spawning.** `spawn.enemy(type, x, y [, {elite = true, difficulty = 3,
onSpawn = fn}])`, `spawn.boss(id [, {x = .., y = .., onSpawn = fn}])` and
`spawn.bullet{x, y, vx, vy, damage, radius, lifetime, fromPlayer, color}`.
Hooks run in the middle of the game's own loops, so spawns happen at the end
of the current frame; use `onSpawn` to set up what you spawned.

**Enemies.** `e:damage(amount [, source])` (bosses too: it drains the current
phase), `e:kill()` (dies with its normal rewards; not bosses), `e:remove()`
(vanishes, no rewards; not bosses), `e:heal(amount)`. The player has
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

There is room for 64 mod power-ups and 32 mod enemies across all loaded mods.
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
* `base = "3d"` makes a mode that plays entirely in a first-person 3D world
  (see [3D worlds](#3d-worlds)): it launches into an empty world that the
  world3d hooks build, `spawning` is off, and finishing the world with
  `world3d.finish(true)` wins the run. Example: `arena_3d`.
* To change an **existing** mode instead, write the same hooks without a mode:
  check `game:isMode("survival")` and so on (see the `survival_tweaks` example).

## Textures, sounds and cosmetics

Files load from your own mod folder (paths relative to it; `..` is refused).

* `assets.texture("sprites/ship.png")` returns a texture (`tex.width`,
  `tex.height`); draw it inside a draw hook with
  `draw.texture(tex, x, y [, {w = .., h = .., rotation = degrees, tint = color,
  origin = "center" | "topleft"}])`.
* Textures are PNG or GIF files, and an **animated GIF** plays by itself
  anywhere a texture goes (`draw.texture`, `override.texture`, cosmetics), at
  the frame delays saved in the file, looping. Every copy on screen shows the
  same frame. `tex.frames` is its number of frames and `tex.duration` one loop
  in seconds (1 and 0 for a still image). To pick the frame yourself, pass
  `frame = n` (1 is the first; it wraps) or `time = seconds` (the frame that
  far into the animation) to `draw.texture`. A delay under 2/100 s plays as
  1/10 s, as in web browsers. GIF transparency is all or nothing per pixel, so
  use a PNG for soft edges.
* `assets.sound("sfx/zap.wav")` returns a sound: `snd:play([volume, pitch])`.
* `override.texture(target, file [, {scale = 1.2, rotate = true}])` draws an
  image (PNG or GIF) instead of one of the game's bodies. Targets: `"player"`, `"enemy:<type>"`,
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
  `waveComplete`, `shield`, `gameOver`, `buy`, ...). WAV, OGG or MP3.
* `override.music(track, file)` replaces a music track: `"menu"`, `"wave"`,
  `"powerUp"` or `"boss"`.
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
| `lit` | true | shaded by the light; `false` for flat colours |
| `tint` | white | a colour multiplied over the model |

Animations are skeletal (a mesh skinned to an armature) in GLB/glTF, IQM and
M3D. They loop at 60 frames per second, which is the speed glTF and M3D
animations were authored at, and up to 128 bones move a mesh. Each enemy
starts its animation at its own point, so a crowd does not flap in step.
Export the skeleton with its armature (Blender does): a root bone with no
parent node cannot be animated here, and the Log tab says so.

Every copy on screen is drawn on its own, so keep enemy models light: a few
hundred triangles each is plenty.

## 3D worlds

The game has a first-person 3D mode (the Orbital Commander boss fight). Mods can
enter it, change it, or build a whole game in it: a world of platforms, enemies
that walk, orbit or shoot, pickups, a tunable weapon and your own HUD. The
`arena_3d` example (**Cube Siege**) is a complete mode built this way, and
`orbital_tweaks` changes the game's own 3D fight.

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
  Winning the world wins the run (the victory screen); losing it, or leaving
  it, ends the run through the death screens.
* **From a 2D run:** `world3d.enter{boss = false, bossId = 7, keepHp = true}`
  opens a world at the end of the frame, through the fade to black. With
  `boss = true` it is the game's own boss fight (`bossId` 7, the Orbital
  Commander, is the authored one). `keepHp` carries the run's HP in and back
  out. When the world ends the run carries on (a won boss fight completes the
  boss wave). It is an error outside a run, while a world is already active,
  or in a run that is a 3D mode already.
* **Leaving:** `world3d.finish(true)` (or `false`, or `"won"` / `"lost"`; no
  argument means won) ends the world as won or lost, and `world3d.exit()` leaves
  it (`"exit"`; in a 3D mode that counts as a loss). Both take effect at the end
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
| `model`, `modelScale`, `modelAnim`, `modelSpeed` | a model from `assets.model` (or a file name); setting one makes the shape `"model"`. `modelScale` 0 fits the model to the entity's diameter; `modelAnim` is an animation number (1 is the first, 0 the rest pose) |
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
  tint])` (a sprite that always faces the camera) and
  `text(text, x, y, z [, size = 20, color])` (a label at a world point, size 10
  to 120). `draw.*` there is an error (`draw.X is 2D: ... use the draw3d
  library`), and so is `draw3d.*` anywhere else.
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
* Gameplay hooks do not run in PvP.

## Shaders

GLSL fragment shaders can post-process the whole frame (desktop OpenGL 3.3,
`#version 330`; see the `retro_crt` example for the inputs raylib passes).

* `assets.shader("fx/crt.fs")` returns a shader. The game fills its `time`
  (seconds) and `resolution` (pixels) uniforms; `shader:set(name, value)` sets
  yours (a number, or a list of 2 to 4 numbers). A shader that does not
  compile is an error with the reason.
* `override.shader("game", shader)` runs it over every frame while a run is on
  screen; `override.shader("screen", shader)` over everything, desktop
  included. Pass `nil` to switch it off.

## The HUD

`hud.hide(part)` hides a piece of the built-in HUD so you can draw your own in
`drawHud`; `hud.show(part)` brings it back and `hud.hidden(part)` asks. Parts:
`"all"`, `"player"` (health, power-ups), `"run"` (the wave / survival /
sector panel), `"boss"`, `"combo"`, `"banners"`, `"abilities"`, `"hints"`,
`"vignettes"`, `"docks"` (the widescreen side panels' background),
`"damageNumbers"` and `"crosshair"` (3D worlds only; `"player"`, `"boss"`
and `"damageNumbers"` also apply there). Every run starts with the full HUD, so hide parts from
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
| `icon` | optional: a texture or model (`assets.texture(...)` / `assets.model(...)`, or a file name: `.png` / `.gif` is a texture, anything else a model) shown in the desktop icon. Without one the icon shows a small window with the app's initial. A model icon also reads the pose options of `override.model` (`tilt`, `spin`, `animation`...) from the same table |
| `color` | optional accent for the window and the icon tile (default: MODS.EXE green) |
| `width`, `height` | optional canvas size in pixels (default 480 x 360; 240-960 wide, 160-640 tall) |
| `resizable` | optional, default `false`. When `true` the player can drag the window's edge: `draw` and `click` then get the current canvas size, so lay out from `w` and `h`. Resizable windows open at least 400 x 300 |
| `desktop` | optional, default `true`. `false` puts no icon on the desktop; the app is still reachable from MODS.EXE > Apps |

The desktop icons of mod apps sit in columns of their own after the game's
icons, in the order the apps were registered, tagged MOD. Opening an app that is
already open just brings its window to the front. Keep settings in
`mod.storage` so they survive restarts (see `retro_crt`).

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
  `draw.text(text, x, y, size, color)` (returns the width),
  `draw.textWidth(text, size)`, and `draw.arena()`, which returns x, y, w, h
  of the arena (in `drawHud`, where it sits on screen: the widescreen side
  panels are outside it). Text is at least size 10.
* Colours: `{r = 255, g = 128, b = 0, a = 255}`, `{255, 128, 0}`, or
  `"#ff8000"` / `"#ff8000cc"`. `color.rgb(r, g, b [, a])` and `color.hex(s)`
  build the table form.
* `lang.text(key)` reads any game string; `lang.current()` is `"en"` or
  `"es"`; `lang.set("en", key, text)` and
  `lang.add({en = {key = "Text"}, es = {key = "Texto"}})` add strings or
  replace the game's own.

## Your mod, the run, other mods

* `mod.id`, `mod.name`, `mod.version`, `mod.author`; `mod.log(...)` and
  `mod.warn(...)` write to the Log tab (so does `print`).
* `run.data` is a table saved with the run: plain numbers, strings, booleans
  and tables survive quitting and resuming (functions do not). You may also
  replace it whole (`run.data = {...}`). `run.active` is true while a run is
  on screen.
* `mod.storage` is a table kept between sessions, per profile (your mod's own
  settings, records or unlocks). It is saved when mods reload and when the game
  closes; `mod.saveStorage()` saves it right away. Same plain-data rule, 1 MB
  at most.
* `mods.export(value)` publishes an API; another mod reads it with
  `mods.get("your_id")` (list yours in its `dependencies` so you load first).
  `mods.isLoaded(id)` and `mods.list()` tell what else is running.

## The examples

**Install Examples** writes these into your mods folder. Pressing it again
replaces an example only when the game ships a newer version of it (a higher
`version` in its `mod.json`), so keep your own changes in a renamed copy:

| Example | Shows |
|---|---|
| `hello_hud` | the basics: hooks, drawing in the arena and on the HUD, run.data |
| `glass_cannon` | a new game mode with its own rules |
| `survival_tweaks` | changing an existing mode (vetoing events, swapping spawns, XP) |
| `bouncer` | a new enemy with its own movement and look, and a new power-up |
| `overclock_boss` | a new boss with scripted attacks and movement, replacing a wave boss |
| `neon_pack` | cosmetics: player skins (one an animated GIF), a bullet trail and a wallpaper (`disableAchievements: false`) |
| `retro_crt` | a post-processing shader, and a desktop app to tune it (`disableAchievements: false`) |
| `house_rules` | a mode that rewrites rules: dash, pickups, the shop, level-ups and its own HUD panel |
| `model_pack` | 3D models: a ship skin, 3D bullets, a voxel desktop cube, an animated enemy and a model viewer app with a 3D icon (`disableAchievements: false`) |
| `arena_3d` | a complete 3D game mode, Cube Siege: waves of entities with built-in AI, pickups, a shotgun tune, a custom HUD, `draw3d` effects and a resumable `run.data` |
| `orbital_tweaks` | changing the game's own 3D boss fight: extra drones, a phase message and a hit filter |

## Multiplayer

PvP lobbies are matched: the host refuses players whose loaded mods (ids,
versions and every file) differ from its own. Gameplay hooks do not run in
PvP; mod cosmetics, textures, models, sounds, text and `"screen"` shaders do.
