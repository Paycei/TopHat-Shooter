# TopHat-ShooterOS mod API

Game version 6.4.0. Generated from the game itself by `nimble modapi`: everything below exists in this build. MODDING.md explains how to use it; this is the complete list.

- [Libraries](#libraries): the tables every mod sees
- [Hooks](#hooks): `hooks.on(name, fn)`
- [The game's procs](#the-games-procs): `engine.<module>.<proc>(...)`, and `mixin.*` for the moddable ones
- [raylib](#raylib): `rl.*` and `rl.gl.*`
- [engine.globals](#engineglobals): the game's global state

## Libraries

The Lua 5.5 standard library is all there too (`io`, `os`, `debug`, `package`, `load`...).

### `advancements`

- `advancements.get`: advancements.get(id) -> {progress, goal, unlocked}
- `advancements.grant`
- `advancements.progress`: advancements.progress(id [, amount = 1]) -> true when this unlocked it

### `assets`

- `assets.exists`: assets.exists("music/boss.ogg") -> is there such a file (or folder) in your mod?
- `assets.font`: local f = assets.font("fonts/pixel.ttf" [, {size = 32, smooth = true, chars = "..."}])
- `assets.json`: assets.json("data/levels.json") -> its value (tables, numbers, strings, booleans)
- `assets.list`: assets.list(["levels"]) -> the names in a folder of your mod, sorted; folders end with "/"
- `assets.model`: local ship = assets.model("models/ship.glb")  -- GLB/glTF, OBJ, IQM, VOX or M3D; mdl.width/height/depth, mdl.animations, mdl:duration(anim)
- `assets.music`: local theme = assets.music("music/theme.ogg"); theme:play()
- `assets.shader`: local crt = assets.shader("fx/crt.fs" [, "fx/crt.vs"])  -- a GLSL fragment shader (and a vertex shader); it gets `time` and `resolution` uniforms, and shader:set(name, value) for yours (numbers, vectors, textures).
- `assets.sound`: local s = assets.sound("sfx/zap.wav"); s:play([volume, pitch])
- `assets.text`: assets.text("data/story.txt") -> the file's contents (a string)
- `assets.texture`: local tex = assets.texture("sprites/ship.png")  -- an image (PNG, JPG, GIF, ...) or a video in your mod folder
- `assets.video`: local clip = assets.video("intro.mpg")  -- MPEG-1 (convert anything else with ffmpeg, see MODDING.md). Goes wherever a texture goes.

### `bosses`

- `bosses.get`: A copy of a boss definition (phases, attacks...), handy to start from.
- `bosses.ids`

### `camera`

- `camera.follow`: camera.follow(on [, lerp]): keep the player centred (lerp = how fast it catches up, per second; 0 snaps)
- `camera.reset`: camera.reset(): the whole arena again
- `camera.toScreen`: camera.toScreen(x, y) -> the screen point (virtual pixels) an arena point is drawn at
- `camera.toWorld`: camera.toWorld(x, y) -> the arena point under a screen point

### `color`

- `color.hex`
- `color.rgb`

### `coop`

- `coop.active`: coop.active() -> boolean: a co-op run is on screen (CO-OP.EXE)
- `coop.isClient`: coop.isClient() -> boolean: this machine draws the host's run; only drawing hooks fire, and what scripts spawn or remove here is dropped
- `coop.isHost`: coop.isHost() -> boolean: this machine simulates the co-op run (gameplay hooks fire here)
- `coop.localSlot`: coop.localSlot() -> number: this machine's seat (0 is the host's, 0 in single player)
- `coop.name`: coop.name(slot) -> string | nil: the nickname at that seat
- `coop.players`: coop.players() -> {player...}: every player of the run, by seat (just the player in single player); player.slot is each one's seat
- `coop.teamLives`: coop.teamLives() -> number | nil: the team's lives left (math.huge when unlimited); nil outside a co-op run

### `difficulty`

- `difficulty.get`: difficulty.get() -> {profile = "gdHard", enemyHp = .., ...} (the scale in force)
- `difficulty.scale`: difficulty.scale{enemyHp = 1.5, enemyDamage = 1.2, enemySpeed = 1, spawnPace = 1.3, eliteChance = 2, bossCooldown = 0.8} -- multipliers on top of the profile's difficulty, for this run (every run starts at 1: set them in runStart)

### `draw`

- `draw.arena`: In drawHud: x, y, w, h of the arena on screen (the docks sit outside it). In drawWorld: 0, 0 and the arena size.
- `draw.circle`
- `draw.circleLines`
- `draw.line`
- `draw.model`: draw.model(mdl, x, y [, {size = px, scale = px per unit, facing = deg, tilt/yaw/pitch/roll = deg, spin = deg/s, animation = name | n | false, speed = x, time = seconds, frame = n, lit = bool, tint = color, key = name | n, fade = seconds}]) Centred on x, y; its footprint (seen from above) is `size` wide (64 by default); its front points toward `facing` (90 = down, the default). With a `key`, a change of animation crossfades over `fade` seconds.
- `draw.poly`: draw.poly(x, y, sides, radius, rotationDegrees, color)
- `draw.rect`
- `draw.rectLines`
- `draw.text`: draw.text(text, x, y, size, color [, font | {font = f, spacing = px}]) -> width in pixels
- `draw.textWidth`: draw.textWidth(text [, size = 10, font | {font = f, spacing = px}])
- `draw.texture`: draw.texture(tex, x, y [, {w = .., h = .., rotation = deg, tint = color, origin = "center" | "topleft", frame = n, time = seconds}]) A GIF plays by itself; frame (1 = first, wraps) or time (seconds into the animation) pick the frame instead.

### `draw3d`

- `draw3d.billboard`: draw3d.billboard(texture, x, y, z [, size = 8, tint]) -- a sprite that always faces the camera
- `draw3d.cube`: draw3d.cube(x, y, z, w, h, d, color) -- centred on x, y, z
- `draw3d.cubeWires`
- `draw3d.cylinder`: draw3d.cylinder(x, y, z, radius, height, color [, slices = 16]) -- centred on x, y, z
- `draw3d.cylinderWires`
- `draw3d.grid`: draw3d.grid([slices = 10, spacing = 1, y = 0]) -- a grid on the floor plane around the origin
- `draw3d.line`: draw3d.line(x1, y1, z1, x2, y2, z2, color)
- `draw3d.model`: draw3d.model(mdl, x, y, z [, {scale, size, yaw, pitch, roll, spin, animation, time, frame, speed, tint, lit, key, fade}]) -- centred on x, y, z. scale = world units per model unit; size = fit its footprint to that many units (default 8). With a `key`, a change of animation crossfades over `fade` seconds.
- `draw3d.plane`: draw3d.plane(x, y, z, w, d, color) -- a flat quad centred on x, y, z, w wide on x, d deep on z
- `draw3d.sphere`: draw3d.sphere(x, y, z, radius, color)
- `draw3d.sphereWires`: draw3d.sphereWires(x, y, z, radius, color [, rings = 8, slices = 8])
- `draw3d.text`: draw3d.text(text, x, y, z [, size = 20, color, font | {font = f, spacing = px}]) -- a label at a world point, drawn over the scene
- `draw3d.texture`: draw3d.texture(texture, x, y, z [, {w, h, yaw, pitch, roll, tint, frame, time}]) -- a flat picture fixed in the world (a sign, a screen, a decal), centred on x, y, z: 8 tall unless given, the missing side from the aspect. Unturned it stands upright facing +z; both sides show it.

### `enemies`

- `enemies.config`: A copy of an enemy type's stats, in the shape override.enemy takes.
- `enemies.types`

### `engine`

- `engine.atLeast`: engine.atLeast("1.12") -> whether this game is that version or newer
- `engine.call`: engine.call("module.proc", ...) -> what the proc returns
- `engine.defer`: engine.defer(fn): run fn at the next safe point (after this frame's simulation, or at the top of the next frame), where lists may grow and shrink.
- `engine.has`: engine.has("screens.go") -> whether the API has it (a dotted path from the globals every mod sees; for the game's procs, mixin.has)
- `engine.globals` (userdata)
- `engine.version` (string)

### `fx`

- `fx.damageNumber`: fx.damageNumber(x, y, amount [, critical])
- `fx.particles`: fx.particles(x, y, color [, count])
- `fx.shake`: fx.shake("small" | "medium" | "large" | "massive")
- `fx.sound`: fx.sound("explosion" [, volume, pitch]) -- the game's built-in sounds

### `hooks`

- `hooks.emit`: hooks.emit("necro:raised", ...) -- every handler of the event, in order
- `hooks.filter`: hooks.filter("necro:soulValue", value, ...) -> the value after every handler (each gets (value, ...) and may return a replacement)
- `hooks.list`
- `hooks.off`
- `hooks.on`: hooks.on("update", function(game, dt) ... end) hooks.on("necro:raised", fn) -- a name with ':' is a mod event (hooks.emit)

### `hud`

- `hud.hidden`
- `hud.hide`: hud.hide("boss") -- until hud.show or the next run (every run starts full)
- `hud.parts`
- `hud.show`

### `input`

- `input.action`: input.action("dash") -> is the player's bound key for it held?
- `input.bind`
- `input.bindPressed`
- `input.bindReleased`
- `input.down`
- `input.mouse`: World coordinates (the arena), like enemy and player positions.
- `input.mouseDown`
- `input.mousePressed`
- `input.pressed`
- `input.released`
- `input.screenMouse`: Screen (HUD) coordinates, for drawHud.

### `lang`

- `lang.add`: lang.add({en = {key = "Text"}, es = {key = "Texto"}})
- `lang.current`: lang.current() -> "en", "es" or the id of the mod language in use
- `lang.list`: lang.list() -> {{id = "en", name = "English"}, {id = "es", ...}, <mod languages>}
- `lang.set`: lang.set("en", "my_key", "Text") -- also overrides built-in strings
- `lang.text`
- `lang.use`: lang.use("fr") -> true: switch the game's language (and the setting); false: no such language is loaded (the game falls back to English)

### `mixin`

- `mixin.after`
- `mixin.before`
- `mixin.has`
- `mixin.list`: mixin.list([prefix]) -> every moddable proc's name (an overload's with its parameter types), sorted
- `mixin.remove`: mixin.remove(handle) -> true if it was installed
- `mixin.replace`
- `mixin.signature`: mixin.signature(name) -> its Nim signature(s), one per line
- `mixin.wrap`: mixin.wrap(name, fn(orig, ...) [, {priority = n}]) -> handle

### `mods`

- `mods.dir`: mods.dir("other_id") -> that loaded mod's folder (nil if it is not loaded)
- `mods.export`: mods.export(value): what other mods get from mods.get("<your id>")
- `mods.get`
- `mods.isLoaded`
- `mods.list`

### `override`

- `override.boss`: override.boss(5, {hp = 900, phases = {...}}) -- replaces what you give
- `override.enemy`: override.enemy("etCircle", {baseHP = 3, baseColor = "#40ff80", movement = {baseSpeed = 160}}) override.enemy("etCube", {update = function(e, dt, game) ... return true end, draw = function(e) ... end})  -- scripted AI / look
- `override.model`: override.model("player", "models/ship.glb" [, {scale = 1.2, rotate = true, tilt = 30, yaw = 0, pitch = 0, roll = 0, spin = 0, animation = "Idle", speed = 1, lit = true, tint = color}]) targets: those of override.texture, and "cube" (the desktop cube) in place of "desktop". nil instead of the model puts the game's own look back.
- `override.music`: override.music("wave" | "menu" | "powerUp" | "boss" | "survival" | "roguelite" | "storyIntro" | "storyRootAccess" | "storyBelow" | "storyUptime", "music/track.ogg")
- `override.powerup`: override.powerup("puDoubleShot", {maxLevel = 5, color = "#ff0000", modes = {"wave"}, update = fn(player, level, dt, game), onHit = fn(bullet, enemy, damage, level) -> damage})
- `override.shader`: override.shader("screen" | "game", shader) -- post-processing over the whole frame; "game" only while a run is on screen. nil switches it off.
- `override.sound`: override.sound("shoot", "sfx/pew.wav")
- `override.text`
- `override.texture`: override.texture("enemy:etCube", "cube.png" [, {scale = 1.2, rotate = true}]) targets: player, enemy:<type>, boss:<id>, bullet:player, bullet:enemy, powerup:<name>, desktop ({cube = true} keeps the desktop cube). nil instead of the texture puts the game's own look back.

### `powerups`

- `powerups.get`: A copy of a power-up's registry entry ({maxLevel, color, pool, ...}).
- `powerups.list`

### `register`

- `register.advancement`: local SLAYER = register.advancement{id = "slayer", name = "Soul Slayer", description = "Raise 100 allies", goal = 100, hidden = false, color = "#a040ff"}
- `register.app`: register.app{id = "settings", name = {en = "Settings", es = "Ajustes"}, draw = function(w, h, mouseX, mouseY) ... end,   -- canvas coordinates update = function(dt) ... end, click = function(x, y, button, w, h) ... end, drag = function(x, y, w, h) ... end, icon = texture | model | "file", color = "#78dca0", width = 480, height = 360, resizable = false, desktop = true}
- `register.boss`: local id = register.boss{name = "OVERCLOCK", hp = 600, phases = {...}}
- `register.command`: register.command{name = "souls", help = {en = "Shows your souls", es = "..."}, run = function(args) return "You have " .. mod.storage.souls .. " souls" end} -- a word the Help terminal runs (on the desktop); args are the words after it
- `register.consumable`: local MANA = register.consumable{id = "mana", name = "Mana", color = "#4080ff", weight = 6, modes = {"wave"}, stats = {damage = "+5%"}, onPickup = fn(player, game, x, y)}
- `register.cosmetic`: register.cosmetic{kind = "player" | "bullet" | "desktop", id = "neon", name = "Neon", colors = {"#ff00ff", "#00ffff", "#ffffff"}, texture = "skins/neon.png", model = "skins/neon.glb", scale = 1.2, rotate = true, plus override.model's pose options (tilt, spin, animation, ...)} desktop only: the texture is the wallpaper (cube = true keeps the desktop cube over it) and the model stands in for the desktop cube
- `register.enemy`: local name = register.enemy{id = "bouncer", base = "etCube", hp = 3, ...}
- `register.gamemode`: register.gamemode{id = "glass", name = "Glass Cannon", description = "...", base = "wave" | "survival" | "roguelite" | "3d", spawning = true, onStart = function(game, resumed) ... end, icon = texture | model | "file", color = "#64c8ff", desktop = true, coop = true}   -- coop = false: CO-OP.EXE does not offer it
- `register.hudCard`: register.hudCard{id = "souls", title = "SOULS", color = "#a040ff", height = 40 | measure = fn(w) -> height, draw = fn(x, y, w, h), classic = true}
- `register.keybind`
- `register.language`: register.language{id = "fr", name = "Francais", base = "en" | "es", strings = {key = "text", ...}} -> "fr": a language of the game, listed in Settings and the first-run picker. Its gaps show the base language. Registering the same id again (another mod, a translation pack) adds strings; lang.set("fr", key, text) does too.
- `register.patch`: local WARD = register.patch{id = "ward", name = "Soul Ward", description = "...", color = "#a040ff", weight = 1, minFloor = 2, stats = {maxHp = 2}, onInstall = fn(player, game), update = fn(player, dt, game)}
- `register.pauseAction`: register.pauseAction{id = "skipIntro", name = "Skip the intro", onClick = fn(game)} -- a button in the pause menu's MODS tab
- `register.powerup`: local name = register.powerup{id = "overdrive", name = "OVERDRIVE.exe", ...}
- `register.projectile`: local BOLT = register.projectile{id = "bolt", pierce = 2, homing = 3, update = fn(bullet, dt, game) -> true moves it yourself, draw = fn(bullet), onHit = fn(bullet, enemy, damage) -> damage, onHitPlayer = fn(bullet, player, damage) -> damage, onExpire = fn(bullet)}
- `register.pvpmode`: register.pvpmode{id = "hill", name = {en = .., es = ..}, description = .., settings = {hp = 5, killLimit = false, timeLimit = 240, teams = false, ...}, onStart = function(match) ... end} -> the mode's key, for match:isMode
- `register.screen`: register.screen{id = "map", enter = fn(from, ...), update = fn(dt), draw = fn(w, h), leave = fn(to), back = fn() -> true keeps it open, cursor = true} -> "<mod id>:map"
- `register.shopItem`: local CORE = register.shopItem{id = "core", name = "Spare Core", description = "+1 wall", cost = 12, costMult = 1.5, maxBuys = 5, modes = {"wave"}, minWave = 3, stats = {walls = 1}, onBuy = fn(player, game, bought)}
- `register.status`: local SOUL = register.status{id = "soulBurn", color = "#a040ff", maxStacks = 5, duration = 4, tickInterval = 0.5, modifiers = {speed = -0.1, damageTaken = 0.15}, onApply = fn(target, stacks, magnitude), onTick = fn(target, stacks, magnitude), onExpire = fn(target), draw = fn(target, x, y, stacks)}
- `register.survivalEvent`: local STORM = register.survivalEvent{id = "storm", name = "Packet Storm", hint = "...", color = "#40c0ff", weights = {boot = 0, runtime = 20, overload = 25, panic = 25}, duration = 20, warmup = 2, reward = "sctStandard" | false, onStart = fn(ev, game), update = fn(ev, game, dt) -> "success" | "fail" | nil, onFinish = fn(ev, game, success), tracker = fn(ev, game) -> text, fraction = fn(ev, game) -> 0..1}
- `register.theme`: register.theme{id = "midnight", name = {en = "Midnight", es = "Medianoche"}, base = "tophat" | "ckn", surface = "#101626", raised = "#2a3350", text = "#f0f4ff", muted = "#8a93a8", accent = "#ff4fd8", wallpaper = "art/wall.png"} -> "<mod id>:midnight" Unset colours come from the base theme.
- `register.thing`: local KIND = register.thing{id = "turret", shape = "circle", radius = 14, team = "player", motion = "static", hp = 20, solid = true, weapon = {interval = 0.6, range = 320, damage = 1}, update = fn, draw = fn, ...}

### `rl`

- `rl.unload`: rl.unload(handle): unload a resource you loaded now (after this frame) instead of when it is dropped -> true; false for a view (the game's).
- `rl.Beige` (table)
- `rl.Black` (table)
- `rl.Blank` (table)
- `rl.Blue` (table)
- `rl.Brown` (table)
- `rl.DarkBlue` (table)
- `rl.DarkBrown` (table)
- `rl.DarkGray` (table)
- `rl.DarkGreen` (table)
- `rl.DarkPurple` (table)
- `rl.Gold` (table)
- `rl.Gray` (table)
- `rl.Green` (table)
- `rl.LightGray` (table)
- `rl.Lime` (table)
- `rl.Magenta` (table)
- `rl.Maroon` (table)
- `rl.Orange` (table)
- `rl.Pink` (table)
- `rl.Purple` (table)
- `rl.RayWhite` (table)
- `rl.Red` (table)
- `rl.SkyBlue` (table)
- `rl.Violet` (table)
- `rl.White` (table)
- `rl.Yellow` (table)

### `roster`

- `roster.add`: roster.add("wave", "mymod:bouncer", {chance = 0.15, fromWave = 3}) (survival: minTime = seconds; roguelite: minFloor = sector)

### `screens`

- `screens.back`: screens.back(): the screen below this one, or the game's state under them all.
- `screens.closeAll`: screens.closeAll(): straight back to the game's state under every screen.
- `screens.current`: screens.current() -> the id of the screen showing, or nil.
- `screens.depth`: screens.depth() -> how many mod screens are open (the one showing included).
- `screens.go`: screens.go(id, ...): open the screen at the top of the next frame; its enter(from, ...) gets the state or screen it came from and these values. Over a run, the run holds still underneath until the screens are left.
- `screens.list`: screens.list() -> every registered screen's id.

### `spawn`

- `spawn.boss`: spawn.boss(id [, {x = .., y = .., onSpawn = fn}])
- `spawn.bullet`: spawn.bullet{x = .., y = .., vx = .., vy = .., damage = 1, radius = 6, lifetime = 3, fromPlayer = false, color = "#ff4040"} -> the bullet, at once (it flies from the end of the frame)
- `spawn.coin`: spawn.coin(x, y [, value])
- `spawn.consumable`: spawn.consumable("ctHealth", x, y) -- or a mod's ("<mod id>:<id>")
- `spawn.enemy`: spawn.enemy("etCube", x, y [, {elite = true, difficulty = 3, onSpawn = fn}]) -> the enemy, at once: it joins the run at the end of the frame (e:valid() is already true; onSpawn runs when it joins).
- `spawn.hazard`: spawn.hazard{shape = "circle" | "rect" | "line" | "ring", x, y, r | w, h | length, angle | inner, warn = 1, active = 0.3, tick = 0, damage = 1, hurts = "player" | "enemies" | "all", color, onTrigger = fn(hazard, game)}
- `spawn.thing`: spawn.thing(kind, x, y [, {overrides..., onSpawn = fn}]) -> the thing, at once
- `spawn.xp`: spawn.xp(x, y [, value])

### `statuses`

- `statuses.list`

### `theme`

- `theme.colors`: theme.colors([id]) -> {id, name, base, light, surface, raised, text, muted, accent} of the theme in use (or of `id`; nil if there is none)
- `theme.current`: theme.current() -> the id of the theme the interface is drawn in
- `theme.glow`: theme.glow(color) -> a translucent highlight in the theme in use
- `theme.ink`: theme.ink(color) -> text (or a glyph) in the theme in use
- `theme.line`: theme.line(color) -> a border or divider in the theme in use
- `theme.list`: theme.list() -> the ids of every theme the player can pick right now
- `theme.overlay`: theme.overlay(color) -> text or a mark straight over the arena (no panel behind it)
- `theme.set`: theme.set(id) -> true: the player's theme is now `id` (saved, as if picked in Settings), even one the player has not unlocked. false: no such theme. Your own themes can be named without the "<mod id>:" prefix.
- `theme.surface`: theme.surface(color) -> a fill (panel, card, button) in the theme in use

### `time`

- `time.hitstop`: time.hitstop(seconds [, scale = 0.05]): freeze the world for a beat (real seconds)
- `time.slowmo`: time.slowmo(seconds, scale [, ramp = false]): slow motion (real seconds), easing back to normal over it with ramp

### `timer`

- `timer.after`
- `timer.cancel`
- `timer.every`

### `ui`

- `ui.banner`: ui.banner(title [, subtitle, color, seconds = 2.5]): a big centred line over the run
- `ui.button`: ui.button(x, y, w, h, label [, {color, enabled = true}]) -> true the frame it is clicked
- `ui.checkbox`: ui.checkbox(x, y, label, checked) -> checked (flipped the frame it is clicked)
- `ui.choose`
- `ui.close`
- `ui.closeAll`: Closes every screen this mod opened.
- `ui.cutscene`
- `ui.dialogue`
- `ui.isOpen`
- `ui.label`: ui.label(text, x, y [, {size = 14, color, align = "left" | "center" | "right", width = px (wraps)}]) -> height drawn
- `ui.open`: local s = ui.open{draw = fn(w, h), update = fn(dt), click = fn(x, y, button), onClose = fn(), pause = true, closeOnBack = true, layer = "hud" | "screen"} -> {id, close = fn, isOpen = fn}. s:close() closes it.
- `ui.panel`: ui.panel(x, y, w, h [, {title, color}]) -> the y below its title
- `ui.pointer`: ui.pointer() -> x, y, pressed, down: the pointer in what you are drawing
- `ui.progress`: ui.progress(x, y, w, h, fraction [, color])
- `ui.slider`: ui.slider(x, y, w, value, min, max) -> value (dragged while held over it)
- `ui.toast`: ui.toast(text): a notification (over the run, or on the desktop)

### `world3d`

- `world3d.active`: world3d.active() -> is a 3D world being played?
- `world3d.aim`: world3d.aim() -> x, y, z, dx, dy, dz: the camera position and where it looks
- `world3d.arena`
- `world3d.boss`: world3d.boss() -> a snapshot table of the boss (read-only copy), nil without one
- `world3d.clearPlatforms`
- `world3d.damageBoss`: world3d.damageBoss(n) -> true if this world has a boss to hurt (its HP is not writable)
- `world3d.damageNumber`: world3d.damageNumber(x, y, z, amount [, color]) -- a floating number
- `world3d.damagePlayer`: world3d.damagePlayer(n [, source = "script"]) -> damage taken (difficulty, invulnerability and hooks apply)
- `world3d.enter`: world3d.enter{boss = false, bossId = 7, keepHp = true} -- from a 2D run; the 3D world opens at the end of the frame (through the fade to black).
- `world3d.entities`: world3d.entities([tag]) -> array of the live entities (those already in the world)
- `world3d.exit`: world3d.exit() -- leave the world ("exit"; the 2D run carries on, a 3D mode's run ends)
- `world3d.finish`: world3d.finish(won) -- end the world as "won" / "lost" (true / false, or the names)
- `world3d.healPlayer`
- `world3d.pickup`
- `world3d.platform`: world3d.platform{x, y, z, w, h, d, ...} -> its 1-based index in world.arena.platforms
- `world3d.projectile`
- `world3d.raycast`: world3d.raycast(x, y, z, dx, dy, dz [, maxDist = 1000]) -> {kind, dist, x, y, z, entity, platform}
- `world3d.shake`: world3d.shake(intensity) -- the camera trembles for `intensity` seconds (max 5)
- `world3d.spawn`
- `world3d.toScreen`: world3d.toScreen(x, y, z) -> screen x, y, visible (in front of the camera and on screen)

## Hooks

`hooks.on(name, function(...) end)`. A *cancel* hook's handler returns true to skip the game's own behaviour; a *filter* hook's returns the replacement for its first argument.


**lifecycle**

| hook | arguments, and what it does |
|---|---|
| `runStart` | (game, resumed) |
| `runEnd` | (game, died) |
| `update` | (game, dt) |
| `preUpdate` | (game, dt) before the simulation |
| `stateChange` | (game, from, to) GameState names |
| `drawBackground` | (game) world coordinates, under everything |
| `drawWorld` | (game) world coordinates |
| `drawHud` | (game, w, h) screen coordinates |
| `drawDesktop` | (w, h) the desktop, over the wallpaper |

**waves and modes**

| hook | arguments, and what it does |
|---|---|
| `waveStart` | (game, wave) |
| `waveEnd` | (game, wave) |
| `waveEnemyCount` | filter (count, game, wave) |
| `waveSpawn` | filter (enemyType, game, wave) -> type name |
| `spawnInterval` | filter (seconds, game) |
| `bossForWave` | filter (bossId, game, wave) |
| `survivalSpawn` | filter (enemyType, game) |
| `survivalEvent` | cancel (game, eventName) |
| `floorStart` | (game, floor) |
| `roomEnter` | (game, room) |
| `roomCleared` | (game, room) |
| `rogueSpawn` | filter (enemyType, game) |

**enemies**

| hook | arguments, and what it does |
|---|---|
| `enemySpawn` | (enemy) |
| `enemyUpdate` | cancel (enemy, dt): true skips the vanilla AI |
| `enemyDraw` | cancel (enemy): true skips the vanilla body |
| `enemyDamaged` | filter (amount, enemy) |
| `enemyDeath` | (enemy, game) |

**bosses**

| hook | arguments, and what it does |
|---|---|
| `bossSpawn` | (boss, game) |
| `bossPhase` | (boss, phaseIndex) |
| `bossAttack` | cancel (boss, attackTable) |
| `bossDeath` | (boss, game) |

**player**

| hook | arguments, and what it does |
|---|---|
| `shoot` | cancel (player, game): true skips the vanilla shot |
| `bulletHit` | filter (damage, bullet, enemy) |
| `playerDamaged` | filter (amount, player) |
| `playerLethal` | cancel (player): true keeps the player alive |
| `playerHeal` | filter (amount, player) |
| `playerDraw` | cancel (player): true skips the vanilla body |
| `playerUpdate` | cancel (player, dt): true skips vanilla movement |
| `dash` | cancel (player): true stops the dash |
| `placeWall` | cancel (x, y, game): true places nothing |
| `ability` | cancel (game): true skips the vanilla [Q] abilities |
| `combatStats` | (player, stats) stats fields can be edited |
| `playerDown` | (player, out) co-op: a player went down (out: no team life was left) |
| `playerRespawn` | (player) co-op: a downed player is back in the fight |

**bullets**

| hook | arguments, and what it does |
|---|---|
| `bulletSpawn` | (bullet) any new bullet, before it flies |
| `bulletUpdate` | cancel (bullet, dt): true skips vanilla movement |
| `bulletDraw` | cancel (bullet): true skips the vanilla body |
| `bulletExpire` | (bullet) its lifetime ran out (not a hit) |

**things**

| hook | arguments, and what it does |
|---|---|
| `thingSpawn` | (thing) a thing joined the arena |
| `thingDeath` | (thing) a thing's HP ran out |

**statuses**

| hook | arguments, and what it does |
|---|---|
| `statusApplied` | (target, name, stacks) enemy or player |
| `statusExpired` | (target, name, expired) gone (expired = ran out, not cleared) |

**more of the game's own moments**

| hook | arguments, and what it does |
|---|---|
| `enemyContact` | filter (damage, enemy, player) an enemy's touch |
| `bulletHitPlayer` | filter (damage, bullet, player) an enemy shot landing |
| `cacheOpen` | cancel (tier, game, x, y) a survival Data Cache opening: true takes it, no rewards |
| `abilityUsed` | (game) the player pressed [Q] (after the abilities ran) |
| `patchInstalled` | (name, game) a roguelite patch was installed (the game's or a mod's) |

**power-ups**

| hook | arguments, and what it does |
|---|---|
| `powerUpChoices` | filter (choicesTable, game) |
| `powerUpPicked` | (name, level, game) |
| `powerUpApply` | cancel (name, level, player): true skips its stat changes |
| `levelUp` | (game, level) |

**restore points**

| hook | arguments, and what it does |
|---|---|
| `checkpoint` | cancel (game): true skips the base mode's restore point |
| `restorePointUsed` | (game, used, max) a Continue spent one; after runStart |
| `xpToLevel` | filter (xp, level, mode) |

**economy**

| hook | arguments, and what it does |
|---|---|
| `coinValue` | filter (amount, enemy) |
| `xpValue` | filter (amount, enemy) |
| `pickup` | cancel (kind, value, game): true = taken, no vanilla effect |
| `shopBuy` | cancel (index, name, cost, game): true = not bought |

**3D worlds**

| hook | arguments, and what it does |
|---|---|
| `world3dStart` | (world, resumed) first frame of a world, before its simulation |
| `world3dPreUpdate` | (world, dt) before the simulation |
| `world3dUpdate` | (world, dt) after the simulation |
| `world3dEnd` | (world, result) "won" \| "lost" \| "exit" |
| `world3dDraw` | (world) inside the 3D camera: draw3d.* allowed |
| `world3dDrawHud` | (world, w, h) screen coordinates over the 3D view |
| `world3dShoot` | cancel (world): true skips the vanilla shot |
| `world3dHit` | filter (damage, target, projectile): target = entity or "boss"/"satellite" |
| `world3dPlayerDamaged` | filter (amount, source, entity) |
| `world3dPlayerLethal` | cancel (): true keeps the player alive |
| `world3dEntitySpawn` | (entity) |
| `world3dEntityUpdate` | cancel (entity, dt): true skips the built-in AI |
| `world3dEntityDraw` | cancel (entity): true skips the built-in body |
| `world3dEntityDeath` | (entity) |
| `world3dBossPhase` | (phase) |
| `world3dBossAttack` | cancel (phase, pattern): true skips the vanilla attack |
| `world3dPickup` | cancel (pickup): true = taken, no vanilla effect |

**PvP**

| hook | arguments, and what it does |
|---|---|
| `pvpStart` | (match) every machine: a match (or rematch) begins |
| `pvpEnd` | (match, winner) every machine: player, team name or nil |
| `pvpFrame` | (match, dt) every machine: each frame of play |
| `pvpUpdate` | (match, dt) host: each frame of play, before the snapshot |
| `pvpDrawBackground` | (match) every machine: arena coordinates, on the floor |
| `pvpDrawWorld` | (match) every machine: arena coordinates, over the world |
| `pvpDrawHud` | (match, w, h) every machine: screen coordinates |
| `pvpPlayerDraw` | cancel (player, match): true skips the body, "all" its labels too |
| `pvpBulletDraw` | cancel (bullet, match): true skips the built-in look |
| `pvpShoot` | cancel (match, player, dirX, dirY, aimX, aimY) host: true replaces the shot |
| `pvpBulletUpdate` | cancel (bullet, dt, match) host: true skips the built-in movement |
| `pvpBulletHit` | filter (damage, bullet, victim, match) host: false = it flies on |
| `pvpPlayerDamaged` | filter (amount, victim, attacker, match) host |
| `pvpPlayerLethal` | cancel (victim, attacker, match) host: true keeps them alive |
| `pvpKill` | (match, victim, killer) every machine (killer may be nil) |
| `pvpRespawn` | (match, player) every machine |
| `pvpSpawnPoint` | (match, player, x, y) host: return x, y to move the spawn |
| `pvpPickup` | cancel (match, player, kind) host: true takes it without its effect |
| `pvpPackage` | filter (kind, match, power) host: the package a port drops next |
| `pvpPlaceWall` | cancel (match, player, x, y) host: true places nothing |
| `pvpEnding` | cancel (match, reason) host: true keeps playing ("kills" \| "time" \| "elimination") |
| `pvpRequest` | (match, player, name, data) host: a player's match:request |
| `pvpBroadcast` | (match, name, data) every machine: the host's match:broadcast |

**the frame**

| hook | arguments, and what it does |
|---|---|
| `frame` | (state, dt) top of every frame, a safe point |
| `screenUpdate` | cancel (state, dt) true replaces this state's update and drawing this frame |
| `screenDraw` | (state, w, h) the frame a screenUpdate took: screen coordinates |
| `drawOverlay` | (state, w, h) every frame, over everything the state drew |

## The game's procs

Every proc here is called from Lua as `engine.<module>.<proc>(...)` (or `engine.call("<module>.<proc>", ...)`); overloads are tried in order. The **moddable** ones can also be wrapped: `mixin.wrap("<module>.<proc>", function(orig, ...) end)`, `before`, `after`, `replace`.


### `abilities`

- **moddable** `activateLegendaries(game: var Game)`
- **moddable** `updateWallPlacement(game: var Game)`

### `advancement`

- **moddable** `advancementPercent(entry: AdvancementEntry, def: AdvancementDefinition): float32`
- **moddable** `advancementProfileToJson(profile: AdvancementProfile): JsonNode` (wrap only: scripts cannot call it)
- **moddable** `allAdvancementCategories(): array[0 .. 4, AdvancementCategory]`
- **moddable** `allAdvancementTiers(): array[0 .. 4, AdvancementTier]`
- **moddable** `categoryDescription(category: AdvancementCategory): string`
- **moddable** `categoryName(category: AdvancementCategory): string`
- **moddable** `categoryTierTotals(profile: AdvancementProfile, category: AdvancementCategory, tier: AdvancementTier): tuple[unlocked: int, total: int, unclaimed: int]`
- **moddable** `categoryTotals(profile: AdvancementProfile, category: AdvancementCategory): tuple[unlocked: int, total: int, unclaimed: int]`
- **moddable** `claimAdvancement(profile: AdvancementProfile, id: string, wallet: RogueliteProfile): tuple[claimed: bool, shards: int, cores: int]`
- **moddable** `claimAllAdvancements(profile: AdvancementProfile, wallet: RogueliteProfile): tuple[count: int, shards: int, cores: int]`
- **moddable** `definitionsForCategory(category: AdvancementCategory): seq[AdvancementDefinition]`
- **moddable** `ensureAdvancementEntries(profile: AdvancementProfile)` (wrap only: scripts cannot call it)
- **moddable** `findEntryIndex(profile: AdvancementProfile, id: string): int` (wrap only: scripts cannot call it)
- **moddable** `formatAdvancementProgress(entry: AdvancementEntry, def: AdvancementDefinition): string`
- **moddable** `getAdvancementDefinition(id: string): AdvancementDefinition`
- **moddable** `getAdvancementDefinitions(): seq[AdvancementDefinition]`
- **moddable** `getAdvancementEntry(profile: AdvancementProfile, id: string): AdvancementEntry`
- **moddable** `getAdvancementsPath(): string` (wrap only: scripts cannot call it)
- **moddable** `isAdvancementUnlocked(profile: AdvancementProfile, id: string): bool`
- **moddable** `jsonToAdvancementProfile(node: JsonNode): AdvancementProfile` (wrap only: scripts cannot call it)
- **moddable** `loadAdvancementCompletionForSlot(slot: int): float32`
- **moddable** `loadAdvancements(): AdvancementProfile`
- **moddable** `newAdvancementProfile(): AdvancementProfile` (wrap only: scripts cannot call it)
- **moddable** `resetAdvancementCategory(profile: AdvancementProfile, category: AdvancementCategory): bool`
- **moddable** `resetAdvancements(profile: AdvancementProfile): bool`
- `rewardCores(def: AdvancementDefinition): int`
- **moddable** `rewardCores(tier: AdvancementTier): int`
- `rewardCores(tier: AdvancementTier): int`
- `rewardShards(def: AdvancementDefinition): int`
- **moddable** `rewardShards(tier: AdvancementTier): int`
- `rewardShards(tier: AdvancementTier): int`
- **moddable** `saveAdvancements(profile: AdvancementProfile): bool`
- `saveAdvancements(profile: AdvancementProfile): bool`
- **moddable** `syncAdvancements(profile: AdvancementProfile, stats: Statistics, lastRun: RunStatistics, rogueliteProfile: RogueliteProfile, liveRun: bool): seq[AdvancementDefinition]`
- **moddable** `tierName(tier: AdvancementTier): string`
- **moddable** `tierTotals(profile: AdvancementProfile, tier: AdvancementTier): tuple[unlocked: int, total: int, unclaimed: int]`
- **moddable** `totalClaimed(profile: AdvancementProfile): int`
- **moddable** `totalUnlocked(profile: AdvancementProfile): int`
- **moddable** `unclaimedShards(profile: AdvancementProfile): int`
- **moddable** `unlockAdvancementDirectly(profile: AdvancementProfile, id: string): bool`

### `advancements_window`

- **moddable** `drawAdvancementsWindow(advWin: AdvancementsWindow)`
- **moddable** `newAdvancementsWindow(screenWidth: int, screenHeight: int, profile: AdvancementProfile, rogueliteProfile: RogueliteProfile): AdvancementsWindow`
- **moddable** `payoutText(def: AdvancementDefinition): string` (wrap only: scripts cannot call it)
- **moddable** `tierColor(tier: AdvancementTier): Color`
- **moddable** `updateAdvancementsWindow(advWin: AdvancementsWindow, dt: float32, screenWidth: int, screenHeight: int, allWindows: openArray[OSWindow]): bool`

### `auras`

- **moddable** `auraPhaseOffset(slot: AuraSlot): float32`
- **moddable** `auraSlotOf(auraType: PowerUpType): AuraSlot`
- **moddable** `auraWaveAlreadyHit(player: Player, enemy: Enemy, slot: AuraSlot): bool`
- **moddable** `auraWaveCatches(player: Player, enemy: Enemy, slot: AuraSlot, frontRadius: float32): bool`
- **moddable** `auraWaveEase(travel: float32): float32` (wrap only: scripts cannot call it)
- **moddable** `auraWaveFrontRadius(elapsed: float32, maxRadius: float32): float32`
- **moddable** `drawAuraEffect(pos: Vector2, config: AuraConfig, time: float32, charge: float32, flash: float32)`
- **moddable** `getAuraConfig(auraType: PowerUpType, level: int): AuraConfig`
- **moddable** `getAuraPulseColor(auraType: PowerUpType): Color`
- **moddable** `getAuraPulseInterval(auraType: PowerUpType, level: int, hasMastery: bool): float32`
- **moddable** `getAuraRadiusFor(auraType: PowerUpType, level: int): float32`
- **moddable** `getAuraRadius(level: int): float32` (wrap only: scripts cannot call it)
- **moddable** `getAuraRangeMult(auraType: PowerUpType): float32` (wrap only: scripts cannot call it)
- **moddable** `markAuraWaveHit(player: Player, enemy: Enemy, slot: AuraSlot)`

### `background_fx`

- **moddable** `drawSharedBackdrop(screenWidth: int32, screenHeight: int32, time: float32, topColor: Color, bottomColor: Color, gridColor: Color, nodeColor: Color, accentColor: Color, starAlphaScale: float32, sweepAlphaScale: float32)`
- **moddable** `drawSoftGlow(centerX: float32, centerY: float32, radius: float32, color: Color, intensity: float32)`

### `boss_3d`

- **moddable** `drawBoss(boss: Boss3D, cam: Camera)`
- **moddable** `drawGravityWells(boss: Boss3D)`
- **moddable** `drawSatelliteHealthbars(boss: Boss3D, camera: FPSCamera)`
- **moddable** `getBoss3D(bossId: int): Boss3D`
- **moddable** `pullIntoWells(boss: Boss3D, player: Player3D, dt: float32)`
- **moddable** `takeBossDamage(boss: var Boss3D, projectile: Projectile3D): tuple[hit: bool, damageDealt: float32, isSatellite: bool, hitPos: Vector3]`
- **moddable** `updateBoss(boss: var Boss3D, player: Player3D, projectiles: var seq[Projectile3D], arena: var Arena3D, dt: float32)`

### `boss_definitions`

- **moddable** `bossAuthoredSlotWave(bossId: int): int`
- **moddable** `bossName(bossNumber: int): string`
- **moddable** `bossRosterProblems(): seq[string]`
- **moddable** `bossSlotDamageRef(slotWave: float32): float32`
- **moddable** `bossSlotHpBudget(slotWave: float32): float32` (wrap only: scripts cannot call it)
- **moddable** `bossWeakPointDefinitionFor(bossID: int): BossWeakPointDefinition` (wrap only: scripts cannot call it)
- **moddable** `bossWeakTier(bossID: int): int` (wrap only: scripts cannot call it)
- **moddable** `clearModBosses()`
- **moddable** `getBossDefinition(bossNumber: int): BossDefinition`
- **moddable** `getBossPhaseHpPools(boss: BossDefinition, scaledHp: float32): seq[float32]`
- **moddable** `getBossProcessName(bossNumber: int): string`
- **moddable** `getBossServiceTag(bossNumber: int): string`
- **moddable** `getCustomBossNumber(waveNumber: int): int`
- **moddable** `getScaledBossDamage(baseBoss: BossDefinition, waveNumber: int): float32`
- **moddable** `getScaledBossHP(baseBoss: BossDefinition, waveNumber: int): float32`
- **moddable** `getScaledBossSpeed(baseBoss: BossDefinition, waveNumber: int): float32`
- `hasModBoss(bossId: int): bool`
- **moddable** `isBossWave(waveNumber: int): bool`
- **moddable** `isRootBoss(bossNumber: int): bool`
- **moddable** `modBossIdsSorted(): seq[int]`
- **moddable** `normalizeBossToSlot(boss: Enemy, slotWave: float32, hpScale: float32)`
- **moddable** `rescaleBossPools(boss: Enemy, factor: float32)` (wrap only: scripts cannot call it)
- **moddable** `vanillaBossDefinition(bossNumber: int): BossDefinition` (wrap only: scripts cannot call it)

### `boss_weakpoints`

- **moddable** `bossWeakPointDamageMultiplier(enemy: Enemy): float32`
- **moddable** `drawBossWeakPoints(enemy: Enemy, showHints: bool)`
- **moddable** `initBossWeakPointState(spec: BossWeakPointDefinition, bossId: int): BossWeakPointState`
- **moddable** `openBossSummonWindow(enemy: Enemy): tuple[opened: bool, bonusDamage: float32]`
- **moddable** `registerBossSatelliteDestroyed(enemy: Enemy): float32`
- **moddable** `resetBossWeakPointForPhase(enemy: Enemy, spec: BossWeakPointDefinition, phaseIndex: int, delay: float32)`
- **moddable** `resolveBossWeakPointTargetHit(enemy: Enemy, bulletPos: Vector2, bulletRadius: float32): BossWeakPointHitResult`
- **moddable** `updateBossWeakPoint(enemy: Enemy, spec: BossWeakPointDefinition, playerPos: Vector2, screenWidth: int32, screenHeight: int32, dt: float32)`

### `bosses`

- **moddable** `addBossAttackWarning(game: var Game, enemy: Enemy, attack: BossAttack)`
- **moddable** `bossLaserActiveDuration(configuredDuration: float32): float32`
- **moddable** `bossLaserThreatRemaining(game: Game): float32`
- **moddable** `bossPhaseMaxHp(enemy: Enemy, phaseIndex: int, phaseCount: int): float32`
- **moddable** `endChargeComboCharge(game: var Game, enemy: Enemy)`
- **moddable** `executeCustomBossAttack(game: var Game, enemy: Enemy, attack: BossAttack, phase: BossPhaseDefinition, bossDef: BossDefinition)`
- **moddable** `livingRoyalGuardCount(game: Game): int`
- **moddable** `retireSatelliteHazards(game: var Game, sat: OrbitalSatellite)`
- **moddable** `spawnArcLattice(game: var Game, enemy: Enemy, attack: BossAttack, phase: BossPhaseDefinition)` (wrap only: scripts cannot call it)
- **moddable** `spawnChaosWeave(game: var Game, enemy: Enemy, attack: BossAttack, phase: BossPhaseDefinition)` (wrap only: scripts cannot call it)
- **moddable** `spawnClockSweep(game: var Game, enemy: Enemy, attack: BossAttack, phase: BossPhaseDefinition)` (wrap only: scripts cannot call it)
- **moddable** `spawnOmegaQuadrants(game: var Game, enemy: Enemy, attack: BossAttack, phase: BossPhaseDefinition)` (wrap only: scripts cannot call it)
- **moddable** `spawnOrbitalSweep(game: var Game, enemy: Enemy, attack: BossAttack, phase: BossPhaseDefinition)` (wrap only: scripts cannot call it)
- **moddable** `spawnPrismRays(game: var Game, enemy: Enemy, attack: BossAttack, phase: BossPhaseDefinition)` (wrap only: scripts cannot call it)
- **moddable** `spawnRicochetLaser(game: var Game, enemy: Enemy, attack: BossAttack, phase: BossPhaseDefinition)` (wrap only: scripts cannot call it)
- **moddable** `spawnSeismicFissure(game: var Game, enemy: Enemy, attack: BossAttack, phase: BossPhaseDefinition)` (wrap only: scripts cannot call it)
- **moddable** `spawnThunderstrike(game: var Game, enemy: Enemy, attack: BossAttack, phase: BossPhaseDefinition)` (wrap only: scripts cannot call it)
- **moddable** `spawnVoidRifts(game: var Game, enemy: Enemy, attack: BossAttack, phase: BossPhaseDefinition)`
- **moddable** `thinnedForLaserOverlap(attack: BossAttack): BossAttack`
- **moddable** `transitionBossToPhase(game: var Game, enemy: Enemy, bossDef: BossDefinition, nextPhaseIndex: int)`
- **moddable** `tryAdvanceBossPhase(game: var Game, enemy: Enemy): bool`
- **moddable** `updateBossMechanics(game: var Game, enemy: Enemy, dt: float32)`
- **moddable** `updateBossSpiralStream(game: var Game, enemy: Enemy, dt: float32)`
- **moddable** `updateChargeCombo(game: var Game, enemy: Enemy, dt: float32)`
- **moddable** `updateCustomBossBehavior(game: Game, enemy: var Enemy, phase: BossPhaseDefinition, dt: float32)`

### `bullet`

- **moddable** `assignBulletId(game: Game, bullet: Bullet)`
- **moddable** `bossBulletShapeFor(bossId: int): int`
- **moddable** `checkBulletEnemyCollision(bullet: Bullet, enemy: Enemy): bool`
- **moddable** `checkBulletPlayerCollision(bullet: Bullet, player: Player): bool`
- **moddable** `checkBulletWallCollision(bullet: Bullet, wall: Wall): bool`
- **moddable** `cloneBullet(original: Bullet, newPos: Vector2, newVel: Vector2, damageMultiplier: float32, speedMultiplier: float32, radiusMultiplier: float32, preventSplit: bool): Bullet` (wrap only: scripts cannot call it)
- **moddable** `createEchoBullet(game: Game, sourceBullet: Bullet, damageMultiplier: float32, speedMultiplier: float32, lifetime: float32)`
- **moddable** `createSplitBullets(game: Game, sourceBullet: Bullet, splitCount: int, damageMultiplier: float32, speedMultiplier: float32)`
- **moddable** `drawBossBulletShape(bullet: Bullet, baseColor: Color, glowColor: Color, gameTime: float32)` (wrap only: scripts cannot call it)
- **moddable** `drawBullet(bullet: Bullet, hasOvercharge: bool, hasBloodBullets: bool, gameTime: float32)`
- **moddable** `isOffScreen(bullet: Bullet, screenWidth: int32, screenHeight: int32): bool`
- **moddable** `newBullet(x: float32, y: float32, direction: Vector2, speed: float32, damage: float32, fromPlayer: bool, isHoming: bool, isPiercing: bool, isExplosive: bool, hasBounce: bool, canSplit: bool, slowAmount: float32, poisonDuration: float32, fireDuration: float32, windPushForce: float32, isPentagon: bool, isEcho: bool, isBossBullet: bool, isArcaneBullet: bool, sourceEnemyId: int, sourceEnemyType: EnemyType, isBonusFromMultiShot: bool, isBonusFromDoubleShot: bool, wasCrit: bool, isSpecialRound: bool, isFromWallTurret: bool, isFromRadialBurst: bool, isFromBulletSplit: bool, isRicochet: bool, isParried: bool, colorOverride: Color, bulletSkin: int, bulletId: int, parentBulletId: int, ownerPlayerIndex: int, bossBulletShape: int, bulletRadius: float32, bulletShape: int): Bullet`
- **moddable** `updateBullet(bullet: Bullet, dt: float32): bool`

### `bullet_shapes`

- **moddable** `drawPlayerBulletShape(pos: Vector2, radius: float32, shape: BulletShapeType, travelAngle: float32, color: Color, glowColor: Color)`
- `getBulletShapeData(s: BulletShapeType): BulletShapeData`
- **moddable** `initializeBulletShapes()`

### `bullet_skins`

- **moddable** `getBulletSkinColors(skinType: BulletSkinType, time: float32): tuple[primary: Color, glow: Color, trail: Color]`
- **moddable** `getBulletSkinData(skinType: BulletSkinType): BulletSkinData`
- **moddable** `initializeBulletSkins()`

### `bullets`

- **moddable** `applyBulletEffects(game: var Game, bullet: Bullet, enemy: Enemy, dt: float32, shielded: bool)`
- **moddable** `applyMasteryDoT(enemy: Enemy, elemType: ElementType, baseDmg: float32, baseDur: float32, hasMastery: bool, masteryDmgMult: float32, masteryDurMult: float32, masterySlowAmount: float32, source: string)`
- **moddable** `blastFreeFizzle(game: var Game, pos: Vector2, color: Color)`
- **moddable** `bossHazardDefused(game: Game, sourceEnemyId: int): bool`
- **moddable** `drawBossDeathBlasts(game: Game)`
- **moddable** `drawLightningBolts(game: Game)`
- **moddable** `drawPathShockwaves(game: Game)`
- **moddable** `drawShockwaveRings(game: Game)`
- **moddable** `getBulletDamageType(bullet: Bullet): DamageType`
- **moddable** `getExplosionRadius(level: int): float32`
- **moddable** `spawnBossDeathBlast(game: var Game, pos: Vector2, maxRadius: float32, sourceEnemyId: int, color: Color)`
- **moddable** `spawnLightningBolt(game: var Game, fromPos: Vector2, toPos: Vector2, color: Color)`
- **moddable** `spawnPathShockwave(game: var Game, points: seq[Vector2], width: float32, color: Color)`
- **moddable** `spawnShockwaveRing(game: var Game, pos: Vector2, maxRadius: float32, color: Color)`
- **moddable** `updateBossDeathBlasts(game: var Game, dt: float32)`
- **moddable** `updateLightningBolts(game: var Game, dt: float32)`
- **moddable** `updatePathShockwaves(game: var Game, dt: float32)`
- **moddable** `updateShockwaveRings(game: var Game, dt: float32)`
- **moddable** `windBulletFlatBonus(player: Player): float32`
- **moddable** `windHitLaunch(force: float32): float32`

### `changelog_window`

- **moddable** `drawChangelogWindow(cl: ChangelogWindow)`
- **moddable** `newChangelogWindow(screenWidth: int, screenHeight: int): ChangelogWindow`
- **moddable** `resetChangelogView(cl: ChangelogWindow)`
- **moddable** `updateChangelogWindow(cl: ChangelogWindow, dt: float32, screenWidth: int, screenHeight: int, allWindows: openArray[OSWindow])`

### `cheat`

- **moddable** `applyPermanentPowerUpCheat(game: var Game, powerUpType: PowerUpType, level: int)` (wrap only: scripts cannot call it)
- **moddable** `applyRogueliteCurrencyCheat(game: var Game, shards: int, cores: int)` (wrap only: scripts cannot call it)
- **moddable** `applyRoguelitePatchCheat(game: var Game, patch: RogueliteRelic): bool` (wrap only: scripts cannot call it)
- **moddable** `applyRoguelitePatchCheat(game: var Game, patch: RogueliteRelicType): bool` (wrap only: scripts cannot call it)
- **moddable** `applyStatCheat(game: var Game, stat: string, value: float32)` (wrap only: scripts cannot call it)
- **moddable** `applySurvivalBossCheat(game: var Game)` (wrap only: scripts cannot call it)
- **moddable** `applySurvivalCacheCheat(game: var Game, tier: SurvivalCacheTier)` (wrap only: scripts cannot call it)
- **moddable** `applySurvivalEventCheat(game: var Game, kind: SurvivalEventKind)` (wrap only: scripts cannot call it)
- **moddable** `applySurvivalJumpToFinalCheat(game: var Game)` (wrap only: scripts cannot call it)
- **moddable** `applySurvivalSkipPhaseCheat(game: var Game)` (wrap only: scripts cannot call it)
- **moddable** `applySurvivalTimeCheat(game: var Game, deltaSeconds: float32)` (wrap only: scripts cannot call it)
- **moddable** `applyWaveCheat(game: var Game, action: string)` (wrap only: scripts cannot call it)
- **moddable** `checkCheatSequence(menu: CheatMenu, game: var Game, currentTime: float32)`
- **moddable** `discoverAllPowerUpsCheat(game: var Game)` (wrap only: scripts cannot call it)
- **moddable** `drawCheatMenu(menu: CheatMenu, game: var Game, screenWidth: int32, screenHeight: int32)`
- **moddable** `initCheatMenu(): CheatMenu`
- **moddable** `removePermanentPowerUpCheat(game: var Game, powerUpType: PowerUpType)` (wrap only: scripts cannot call it)
- **moddable** `setGameModesUnlockedCheat(unlocked: bool)` (wrap only: scripts cannot call it)
- **moddable** `undiscoverAllPowerUpsCheat(game: var Game)` (wrap only: scripts cannot call it)
- **moddable** `updateCheatMenu(menu: CheatMenu, game: var Game)`

### `cinematic_common`

- **moddable** `beginStoryCamera(focusX: float32, focusY: float32, screenX: float32, screenY: float32, scale: float32)`
- **moddable** `cinematicEnemy(enemyType: EnemyType, x: float32, y: float32, difficulty: float32, id: int, threat: int): Enemy` (wrap only: scripts cannot call it)
- **moddable** `drawCenteredText(text: string, x: int32, y: int32, size: int32, color: Color)`
- **moddable** `drawCinematicBoss(boss: Enemy, x: float32, y: float32, radius: float32, hpFraction: float32, phaseIndex: int)`
- **moddable** `drawCinematicOverlay(screenWidth: int32, screenHeight: int32, time: float32, frame: int, scanlineOffset: float32, totalDuration: float32, shotLabel: string, liveText: string, iconIndex: int, glitchHot: bool, controls: CinematicControls, accent: Color)`
- **moddable** `drawCrashPanel(sw: int32, sh: int32, alpha: float32, time: float32)`
- **moddable** `drawEquippedBulletModel(pos: Vector2, radius: float32, travelAngle: float32, time: float32, alpha: float32)`
- **moddable** `drawEquippedPlayerModel(pos: Vector2, radius: float32, time: float32, alpha: float32, glowBoost: float32)`
- **moddable** `drawFilmGrain(screenWidth: int32, screenHeight: int32, time: float32, alpha: float32)` (wrap only: scripts cannot call it)
- **moddable** `drawFootageFrame(sw: int32, sh: int32, scale: float32, alpha: float32)`
- **moddable** `drawHalo(centerX: float32, centerY: float32, radius: float32, color: Color, intensity: float32)`
- **moddable** `drawKernelModel(pos: Vector2, radius: float32, time: float32, boot: float32, alpha: float32, hat: bool)`
- **moddable** `drawOldText(text: string, x: int32, y: int32, size: int32, reveal: float32, local: float32, alpha: float32, color: Color, centered: bool, cursor: bool)`
- **moddable** `drawRealEnemy(enemyType: EnemyType, x: float32, y: float32, radius: float32, time: float32, id: int, threat: int, vel: Vector2)`
- **moddable** `drawServiceWindow(x: float32, y: float32, w: float32, title: string, colService: string, colOwner: string, names: openArray[string], flipTimes: openArray[float32], local: float32, alpha: float32, fromOwner: string, toOwner: string, fromColor: Color, toColor: Color)`
- **moddable** `drawStoryButton(x: float32, y: float32, w: float32, h: float32, label: string, alpha: float32, pressed: bool, primary: bool)`
- **moddable** `drawStoryPointer(x: float32, y: float32, alpha: float32, pressed: bool)`
- **moddable** `drawStoryProgress(x: float32, y: float32, w: float32, h: float32, frac: float32, alpha: float32, color: Color)`
- **moddable** `drawStoryWindow(x: float32, y: float32, w: float32, h: float32, title: string, alpha: float32, iconColor: Color, border: Color)`
- **moddable** `drawSubtitlesFrom(lines: openArray[string], startAt: float32, screenWidth: int32, screenHeight: int32, alpha: float32)`
- **moddable** `drawSubtitles(lines: openArray[string], screenWidth: int32, screenHeight: int32, alpha: float32)`
- **moddable** `drawTapeChange(screenWidth: int32, screenHeight: int32, local: float32, frame: int, time: float32)`
- **moddable** `endStoryCamera()`
- **moddable** `equippedBulletShape(): BulletShapeType` (wrap only: scripts cannot call it)
- **moddable** `equippedBulletSkin(): BulletSkinType` (wrap only: scripts cannot call it)
- **moddable** `equippedShape(): ShapeType` (wrap only: scripts cannot call it)
- **moddable** `equippedSkin(): SkinType` (wrap only: scripts cannot call it)
- **moddable** `newCinematicBoss(bossId: int, screenWidth: int32, screenHeight: int32): Enemy`
- **moddable** `revealOver(local: float32, startAt: float32, dur: float32): float32`
- **moddable** `serviceWindowHeight(rows: int): float32` (wrap only: scripts cannot call it)
- **moddable** `triAny(a: Vector2, b: Vector2, c: Vector2, col: Color)`

### `coin`

- **moddable** `awardMetaCurrency(game: Game, shards: int, cores: int)`
- **moddable** `coinPickupValue(player: Player, value: int): int`
- **moddable** `collectAllCoins(game: Game)`
- **moddable** `collectPickup(game: Game, coin: Coin): bool`
- **moddable** `drawCoin(coin: Coin)` (wrap only: scripts cannot call it)
- **moddable** `drawGameCoins(game: Game)`
- **moddable** `dropEnemyCoin(game: Game, enemy: Enemy)`
- **moddable** `enemyCoinValue(enemy: Enemy, mode: GameMode, currentWave: int, difficulty: float32): int` (wrap only: scripts cannot call it)
- **moddable** `newCoin(x: float32, y: float32, value: int, isBoss: bool): Coin`
- **moddable** `pickupAlive(game: Game, coin: Coin, dt: float32, count: int): bool`
- **moddable** `pickupTrail(coin: Coin): Color`
- **moddable** `spawnMagnetCoins(game: Game)`
- **moddable** `updateGameCoins(game: Game, dt: float32): bool`

### `combat`

- **moddable** `accumulateAndShowAuraDamage(game: Game, enemy: Enemy, actualDamage: float32, damageType: DamageType, wasCrit: bool)`
- **moddable** `accumulateAndShowContactDamage(game: Game, enemy: Enemy, actualDamage: float32)`
- **moddable** `accumulateDotDamage(game: Game, enemy: Enemy, elementType: ElementType, actualDamage: float32)`
- **moddable** `applyBossArenaCombatBonus(game: Game, stats: var CombatStats)`
- **moddable** `applyCriticalHitFromStats(stats: CombatStats, baseDamage: float32): float32`
- **moddable** `applyCriticalHitWithFlag(stats: CombatStats, baseDamage: float32): tuple[damage: float32, wasCrit: bool]`
- **moddable** `applyEnemyHpDamage(enemy: Enemy, damage: float32): float32`
- **moddable** `applyThornsReflection(game: var Game, player: Player, damageToReflect: float32, targetEnemy: Enemy, reflectType: string): float32`
- **moddable** `bossPassiveDamageTaken(enemy: Enemy): float32`
- **moddable** `calculateCombatStats(player: Player): CombatStats`
- **moddable** `calculateContactDamageToEnemy(player: Player, enemy: Enemy): tuple[damage: float32, wasCrit: bool]`
- **moddable** `damageEnemy(enemy: Enemy, baseDamage: float32, consumesDiamondShield: bool): float32`
- **moddable** `densityHealScale(game: Game): float32`
- **moddable** `dotNumberInterval(elementType: ElementType): float32` (wrap only: scripts cannot call it)
- **moddable** `flushAccumulatedAuraDamage(game: Game, enemy: Enemy)`
- **moddable** `flushAccumulatedContactDamage(game: Game, enemy: Enemy)`
- **moddable** `flushAccumulatedDotDamage(game: Game, enemy: Enemy)`
- **moddable** `flushAccumulator(game: Game, enemy: Enemy, acc: var DamageAccumulator)` (wrap only: scripts cannot call it)
- **moddable** `rageDamageMultiplier(player: Player): float32`
- **moddable** `setEnemyHp(enemy: Enemy, hp: float32)`
- **moddable** `shieldBlocksHit(game: Game, enemy: Enemy, hitFrom: Vector2): bool`
- **moddable** `showCurrency(game: Game, pos: Vector2, amount: int, kind: CurrencyIndicatorKind)`
- **moddable** `showDamage(game: Game, pos: Vector2, damage: float32, fromPlayer: bool, isCritical: bool, damageType: DamageType)`
- **moddable** `showPerk(game: Game, pos: Vector2, text: string, color: Color)`
- **moddable** `showPlayerDamageTaken(game: Game, damageType: DamageType)`
- **moddable** `tickAccumulator(game: Game, enemy: Enemy, acc: var DamageAccumulator, damage: float32, damageType: DamageType, wasCrit: bool, interval: float32)` (wrap only: scripts cannot call it)

### `consumable`

- **moddable** `consumableColor(c: Consumable): Color`
- **moddable** `consumablePerkLabel(c: Consumable): string`
- **moddable** `drawConsumableIcon(x: float32, y: float32, cType: ConsumableType)` (wrap only: scripts cannot call it)
- **moddable** `drawConsumable(consumable: Consumable)`
- **moddable** `newConsumable(x: float32, y: float32, difficulty: float32, mode: GameMode): Consumable`
- **moddable** `newSpecificConsumable(x: float32, y: float32, cType: ConsumableType): Consumable`
- **moddable** `pickupAlive(game: Game, consumable: Consumable, dt: float32, count: int): bool`
- **moddable** `pickupTrail(consumable: Consumable): Color`
- **moddable** `startConsumableBuff(player: Player, ct: ConsumableType)`

### `coop_codec`

- **moddable** `applySnapshot(frame: WireFrame, game: Game)`
- **moddable** `captureFrame(game: Game, seq: int32): WireFrame`
- **moddable** `encodeSnapshot(cur: WireFrame, base: WireFrame, extras: SnapExtras): string`
- **moddable** `readSnapshot(packed: string, ring: FrameRing, extras: var SnapExtras): WireFrame`

### `coop_overlay`

- **moddable** `coopName(game: Game, slot: int): string`
- **moddable** `coopPauseMenu(host: bool): int`
- **moddable** `coopResultsPanel(game: Game, reason: string, kills: int): bool`
- **moddable** `drawCoopBanner(text: string)`
- **moddable** `drawCoopLocalDown(game: Game)`
- **moddable** `drawCoopModalStatus(game: Game)`
- **moddable** `drawCoopTeamStrip(game: Game, x: int32, y: int32, w: int32): int32`

### `coop_present`

- **moddable** `replayCoopFx(game: var Game)`

### `coop_profile`

- **moddable** `applyProfileEvent(ev: ProfileEvent, advProfile: AdvancementProfile): string`

### `coop_session`

- **moddable** `backToLobby(s: CoopSession)`
- **moddable** `broadcastLobby(s: CoopSession)`
- **moddable** `closeCoop(s: CoopSession, reason: string)`
- **moddable** `endCoopRun(s: CoopSession, reason: CoopEndReason)`
- **moddable** `endStatistics(s: CoopSession): RunStatistics`
- **moddable** `hostCoop(port: int, maxPlayers: int, me: CoopMemberNet, config: CoopRunConfigNet): CoopSession`
- **moddable** `joinCoop(host: string, port: int, me: CoopMemberNet): CoopSession`
- **moddable** `pollCoopSession(s: CoopSession, game: Game, dt: float32)`
- **moddable** `readyToStart(s: CoopSession): bool`
- **moddable** `setLobbyConfig(s: CoopSession, config: CoopRunConfigNet)`
- **moddable** `setReady(s: CoopSession, ready: bool, kit: int32)`
- **moddable** `startCoopRun(s: CoopSession)`

### `coop_smooth`

- **moddable** `afterSnapshot(game: Game, intentAck: int32)`
- **moddable** `beforeSnapshot(game: Game)`
- **moddable** `predictLocal3D(game: Game, dt: float32, seq: int32)`
- **moddable** `predictLocal(game: Game, dt: float32, seq: int32)`
- **moddable** `smoothFrame3D(game: Game, dt: float32, age: float32)`
- **moddable** `smoothFrame(game: Game, dt: float32, age: float32)`

### `coop_window`

- **moddable** `drawCoopWindow(cw: CoopWindow)`
- **moddable** `modeChoices(): seq[ModeChoice]`
- **moddable** `newCoopWindow(screenWidth: int, screenHeight: int): CoopWindow`
- **moddable** `resetCoopView(cw: CoopWindow)`
- **moddable** `updateCoopWindow(cw: CoopWindow, dt: float32, screenWidth: int, screenHeight: int, allWindows: openArray[OSWindow])`
- **moddable** `wantsTextInput(cw: CoopWindow): bool`

### `credits_window`

- **moddable** `drawCreditsWindow(cw: CreditsWindow)`
- **moddable** `newCreditsWindow(screenWidth: int, screenHeight: int): CreditsWindow`
- **moddable** `updateCreditsWindow(cw: CreditsWindow, dt: float32, screenWidth: int, screenHeight: int, allWindows: openArray[OSWindow])`

### `cube_render`

- **moddable** `drawZeroGravityWallpaperCube(centerX: float32, centerY: float32, size: float32, time: float32, angleX: float32, angleY: float32, angleZ: float32, skin: CubeSkinType, glowBoost: float32, compact: bool)`
- **moddable** `projectCubePoint(point: Vector3, centerX: float32, centerY: float32, scale: float32): Vector2` (wrap only: scripts cannot call it)
- **moddable** `rotateCubePoint(point: Vector3, angleX: float32, angleY: float32, angleZ: float32): Vector3` (wrap only: scripts cannot call it)

### `cube_skins`

- **moddable** `getCubeSkinData(skinType: CubeSkinType): CubeSkinData`
- **moddable** `initializeCubeSkins()`

### `cutscene`

- **moddable** `drawCutscene(c: Cutscene, sw: int, sh: int)`
- **moddable** `newCutscene(shots: seq[CutsceneShot], accentColor: Color, titleCardText: string, titleCardSub: string, drawBackdropProc: CutsceneBackdropProc, swayAmp: float32, skipHoldRequired: float32, fastForwardMult: float32, musicTrack: MusicTrack, cornerTag: string, playbackSpeed: float32, speaker: string, captionCps: float32): Cutscene` (parameter drawBackdropProc is a CutsceneBackdropProc)
- **moddable** `shotAt(c: Cutscene, time: float32): tuple[idx: int, local: float32, duration: float32]` (wrap only: scripts cannot call it)
- **moddable** `shotFade(local: float32, duration: float32): float32` (wrap only: scripts cannot call it)
- **moddable** `updateCutscene(c: Cutscene, dt: float32)`

### `d_enhancements`

- **moddable** `drawBossIntroductionGutter(intro: BossIntroduction, gutterX: int32, gutterW: int32, topY: int32): int32`
- **moddable** `drawBossIntroduction(intro: BossIntroduction, screenWidth: int32, screenHeight: int32)`
- **moddable** `drawWaveCelebrationGutter(celebration: WaveCelebration, gutterX: int32, gutterW: int32, topY: int32): int32`
- **moddable** `drawWaveCelebration(celebration: WaveCelebration, screenWidth: int32, screenHeight: int32, originX: int32)`
- **moddable** `newBossIntroduction(): BossIntroduction`
- **moddable** `newRealTimeStats(): RealTimeStats`
- **moddable** `newWaveCelebration(): WaveCelebration`
- **moddable** `recordDamage(stats: var RealTimeStats, damage: float32, currentTime: float32)`
- **moddable** `startCelebration(celebration: var WaveCelebration, waveNum: int, stats: WaveStats)`
- **moddable** `startIntroduction(intro: var BossIntroduction, name: string, title: string, tag: string, isRoot: bool)`
- **moddable** `updateCelebration(celebration: var WaveCelebration, dt: float32): bool`
- **moddable** `updateIntroduction(intro: var BossIntroduction, dt: float32): bool`

### `d_systems`

- **moddable** `activateCustomSlowMo(slowMo: var SlowMotion, scale: float32, duration: float32, ramp: bool)`
- **moddable** `activateSlowMo(slowMo: var SlowMotion, slowType: SlowMotionType)`
- **moddable** `addComboKill(combo: var ComboSystem, currentTime: float32): int`
- **moddable** `addShake(shake: var ScreenShake, intensity: ShakeIntensity, tint: Color)`
- **moddable** `calculateAccuracy(stats: var WaveStats)`
- **moddable** `checkPerfectWaveCombo(combo: var ComboSystem, waveEnemyCount: int): int`
- **moddable** `getComboMultiplier(combo: ComboSystem): string`
- **moddable** `getComboWindow(combo: ComboSystem): float32` (wrap only: scripts cannot call it)
- **moddable** `getShakeOffset(shake: ScreenShake): Vector2`
- **moddable** `initEnhancedDopamine(dopamine: var DopamineState)`
- **moddable** `newComboSystem(): ComboSystem`
- **moddable** `newDopamineState(): DopamineState`
- **moddable** `newMicroRewardTracker(): MicroRewardTracker`
- **moddable** `newScreenShake(): ScreenShake`
- **moddable** `newSlowMotion(): SlowMotion`
- **moddable** `newWaveStats(waveNumber: int): WaveStats` (wrap only: scripts cannot call it)
- **moddable** `recordCombo(stats: var WaveStats, combo: int)`
- **moddable** `resetWaveStats(dopamine: var DopamineState, waveNumber: int)`
- **moddable** `shouldShowCombo(combo: ComboSystem): bool`
- **moddable** `startWaveCombo(combo: var ComboSystem)`
- **moddable** `triggerHitStop(slowMo: var SlowMotion, duration: float32, scale: float32)`
- **moddable** `updateCombo(combo: var ComboSystem, dt: float32, currentTime: float32)` (wrap only: scripts cannot call it)
- **moddable** `updateDopamine(dopamine: var DopamineState, dt: float32)`
- **moddable** `updateRewards(tracker: var MicroRewardTracker, dt: float32)` (wrap only: scripts cannot call it)
- **moddable** `updateShake(shake: var ScreenShake, dt: float32)`
- **moddable** `updateSlowMo(slowMo: var SlowMotion, realDt: float32)` (wrap only: scripts cannot call it)
- **moddable** `updateStats(stats: var WaveStats, dt: float32)` (wrap only: scripts cannot call it)
- **moddable** `worldTimeScale(slowMo: SlowMotion): float32`

### `d_visuals`

- **moddable** `drawComboAtPosition(combo: ComboSystem, screenWidth: int32, screenHeight: int32, currentTime: float32, posX: int32, posY: int32)`
- **moddable** `drawComboGutterCard(combo: ComboSystem, gutterX: int32, gutterW: int32, topY: int32, currentTime: float32)`
- **moddable** `drawCombo(combo: ComboSystem, screenWidth: int32, screenHeight: int32, currentTime: float32)`
- **moddable** `drawLabelBannerGutter(title: string, subtitle: string, age: float32, gutterX: int32, gutterW: int32, topY: int32, accent: Color, duration: float32): int32`
- **moddable** `drawLabelBanner(title: string, subtitle: string, age: float32, screenWidth: int32, topY: int32, accent: Color, duration: float32)`
- **moddable** `drawMicroRewards(tracker: MicroRewardTracker)`
- **moddable** `drawWaveStartBannerGutter(waveNumber: int, waveAge: float32, gutterX: int32, gutterW: int32, topY: int32, isBossWarning: bool): int32`
- **moddable** `drawWaveStartBanner(waveNumber: int, waveAge: float32, screenWidth: int32, screenHeight: int32, isBossWarning: bool)`

### `death`

- **moddable** `beginPlayerDeathSequence(game: Game, cause: DeathCause, source: Enemy, sourceType: EnemyType)`
- **moddable** `coopTeamWiped(game: Game): bool`
- **moddable** `drawRecentPowerUpInstall(game: Game)`
- **moddable** `installPowerUp(game: var Game, powerUp: PowerUp, quiet: bool)`
- **moddable** `showInstallCard(game: Game, powerUp: PowerUp)`
- **moddable** `spawnPlayerDeathExplosion(game: Game, deathPos: Vector2)`
- **moddable** `updateDeathSequencePlayback(game: var Game, dt: float32)`
- **moddable** `updateDownedPlayers(game: var Game, dt: float32)`

### `desktop_bg_fx`

- **moddable** `drawDesktopBgScene(bgType: DesktopBgType, screenWidth: int32, screenHeight: int32, time: float32)`

### `desktop_bg_skins`

- **moddable** `getDesktopBgData(bgType: DesktopBgType): DesktopBgData`
- **moddable** `initializeDesktopBgSkins()`

### `draw_prims`

- `drawBandArc(center: Vector2, innerRadius: float32, outerRadius: float32, startAngle: float32, endAngle: float32, edgeColor: Color, midColor: Color)`
- `drawCircleOutline(center: Vector2, radius: float32, color: Color)`
- `drawCircleOutline(center: Vector2, radius: float32, thick: float32, color: Color)`
- `drawCircleOutline(centerX: int32, centerY: int32, radius: float32, color: Color)`
- `drawDashedRing(center: Vector2, radius: float32, halfWidth: float32, dashes: int, fill: float32, phase: float32, color: Color)`
- `drawDisc(center: Vector2, radius: float32, color: Color)`
- `drawDisc(centerX: int32, centerY: int32, radius: float32, color: Color)`
- `drawEllipseOutline(center: Vector2, radiusH: float32, radiusV: float32, color: Color)`
- `drawEllipseOutline(center: Vector2, radiusH: float32, radiusV: float32, thick: float32, color: Color)`
- `drawEllipseOutline(centerX: int32, centerY: int32, radiusH: float32, radiusV: float32, color: Color)`
- `drawFadeStroke(a: Vector2, b: Vector2, width: float32, color: Color)`
- `drawGlowLine(a: Vector2, b: Vector2, width: float32, color: Color)`
- `drawGlow(center: Vector2, radius: float32, color: Color)`
- `drawGlow(center: Vector2, radiusX: float32, radiusY: float32, color: Color)`
- `drawGradientQuad(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, c0: Color, c1: Color, c2: Color, c3: Color)`
- `drawGradientRing(center: Vector2, innerRX: float32, innerRY: float32, outerRX: float32, outerRY: float32, innerColor: Color, outerColor: Color)`
- `drawGradientRing(center: Vector2, innerRadius: float32, outerRadius: float32, innerColor: Color, outerColor: Color)`
- `drawGradientTriangle(p0: Vector2, p1: Vector2, p2: Vector2, c0: Color, c1: Color, c2: Color)`
- `drawPolyOutline(center: Vector2, sides: int32, radius: float32, rotation: float32, color: Color)`
- `drawPolyOutline(center: Vector2, sides: int32, radius: float32, rotation: float32, thick: float32, color: Color)`
- `drawRadialGradient(center: Vector2, radiusX: float32, radiusY: float32, inner: Color, outer: Color, ease: RadialEase, rings: int)`
- `drawRectOutline(posX: int32, posY: int32, width: int32, height: int32, color: Color)`
- `drawRectOutline(rec: Rectangle, thick: float32, color: Color)`
- `drawSoftRing(center: Vector2, radius: float32, halfWidth: float32, color: Color)`
- `drawStroke(startPos: Vector2, endPos: Vector2, color: Color)`
- `drawStroke(startPos: Vector2, endPos: Vector2, thick: float32, color: Color)`
- `drawStroke(startPosX: int32, startPosY: int32, endPosX: int32, endPosY: int32, color: Color)`
- `drawTaperedLine(a: Vector2, b: Vector2, widthA: float32, widthB: float32, colorA: Color, colorB: Color)`
- `drawTriangleOutline(v1: Vector2, v2: Vector2, v3: Vector2, color: Color)`
- `drawTriangleOutline(v1: Vector2, v2: Vector2, v3: Vector2, thick: float32, color: Color)`

### `dungeon`

- **moddable** `appendRoom(game: Game, exitIdx: int): DungeonRoom`
- **moddable** `beginSectorRooms(game: Game)`
- **moddable** `claimDungeonPickup(game: Game, index: int): DungeonFrame` (wrap only: scripts cannot call it)
- **moddable** `consumeDungeonSpawn(game: Game)`
- **moddable** `currentDungeonRoom(run: RogueliteRun): DungeonRoom`
- **moddable** `doorRect(game: Game, dir: DoorDir): Rectangle` (wrap only: scripts cannot call it)
- **moddable** `doorSpawnPos(game: Game, enteredThrough: DoorDir): Vector2` (wrap only: scripts cannot call it)
- **moddable** `drawDungeonOverlay(game: Game)`
- **moddable** `drawProximityCard(card: ProximityCard, anchorX: float32, anchorY: float32, worldW: int32, worldH: int32, time: float32)` (wrap only: scripts cannot call it)
- **moddable** `dungeonBossNumberFor(theme: DungeonFloorTheme, floorNumber: int, endlessLoop: int, heat: int): int`
- **moddable** `dungeonBossNumber(game: Game): int`
- **moddable** `dungeonDensityWave(run: RogueliteRun, room: DungeonRoom): int` (wrap only: scripts cannot call it)
- **moddable** `dungeonEffectiveThreat(run: RogueliteRun, room: DungeonRoom): int`
- **moddable** `dungeonEliteRoll(run: RogueliteRun, room: DungeonRoom): int`
- **moddable** `dungeonEnemyDifficulty(run: RogueliteRun, room: DungeonRoom): float32`
- **moddable** `dungeonRoomWaveEquivalent(run: RogueliteRun, room: DungeonRoom): float32`
- **moddable** `dungeonSpawnAllowance(game: Game): int`
- **moddable** `enterRoom(game: Game, roomIdx: int, enteredThrough: DoorDir, resumed: bool)`
- **moddable** `exitPortalPos(game: Game): Vector2` (wrap only: scripts cannot call it)
- **moddable** `exitsOf(floor: DungeonFloor, room: DungeonRoom): seq[DungeonExit]` (wrap only: scripts cannot call it)
- **moddable** `exitsOpen(room: DungeonRoom): bool` (wrap only: scripts cannot call it)
- **moddable** `generateFloor(game: Game, theme: DungeonFloorTheme, floorNumber: int): DungeonFloor`
- **moddable** `generateThemeChoices(run: RogueliteRun)`
- **moddable** `isFinalDungeonFloor(run: RogueliteRun): bool`
- **moddable** `isStall(kind: DungeonPickupKind): bool` (wrap only: scripts cannot call it)
- **moddable** `markBossRoomCleared(game: Game)`
- **moddable** `noCreditsLabel(): string` (wrap only: scripts cannot call it)
- **moddable** `onRoomCleared(game: Game)`
- **moddable** `pickupRelic(pk: DungeonPickup): RogueliteRelic` (wrap only: scripts cannot call it)
- **moddable** `rewardAccent(reward: RoomReward): Color` (wrap only: scripts cannot call it)
- **moddable** `rewardFolderName(reward: RoomReward): string`
- **moddable** `rewardLabel(reward: RoomReward): string`
- **moddable** `rollEncounterEnemyType(run: RogueliteRun, room: DungeonRoom): EnemyType`
- **moddable** `roomGoal(game: Game): RoomGoal`
- **moddable** `sectorPath(floor: DungeonFloor): string`
- **moddable** `sectorRewardLayers(floor: DungeonFloor): int`
- **moddable** `selectFloorTheme(game: Game, choiceIndex: int)`
- **moddable** `spawnRogueliteExitPortal(game: Game)`
- **moddable** `spawnRoomReward(game: Game, room: DungeonRoom)` (wrap only: scripts cannot call it)
- **moddable** `spawnShopStalls(game: Game, room: DungeonRoom)` (wrap only: scripts cannot call it)
- **moddable** `stallPrice(game: Game, room: DungeonRoom, pickup: DungeonPickup): int` (wrap only: scripts cannot call it)
- **moddable** `startDungeonFloor(game: Game, theme: DungeonFloorTheme)`
- **moddable** `themeAccent(theme: DungeonFloorTheme): Color`
- **moddable** `themeDef(theme: DungeonFloorTheme): DungeonThemeDef`
- **moddable** `themeDescription(theme: DungeonFloorTheme): string`
- **moddable** `themeFolder(theme: DungeonFloorTheme): string`
- **moddable** `themeName(theme: DungeonFloorTheme): string`
- **moddable** `tuneDungeonBossStats(boss: Enemy, run: RogueliteRun)`
- **moddable** `tuneDungeonEnemyStats(enemy: Enemy, run: RogueliteRun, room: DungeonRoom)`
- **moddable** `updateDungeon(game: Game, dt: float32): DungeonFrame`
- **moddable** `wipeRoomEntities(game: Game)` (wrap only: scripts cannot call it)

### `effects`

- **moddable** `applyEffect(enemy: Enemy, effectType: ElementType, damagePerSec: float32, duration: float32, source: string, hadMastery: bool)`
- **moddable** `hasActiveEffect(enemy: Enemy, elementType: ElementType): bool`
- **moddable** `poisonStackCap(enemy: Enemy): float32`
- **moddable** `poisonStackMultiplier(enemy: Enemy): float32`
- **moddable** `updateEffects(enemy: Enemy, dt: float32): float32`

### `endgame_cinematic`

- **moddable** `drawEndgameCinematic(endg: EndgameCinematic, screenWidth: int, screenHeight: int)`
- `newEndgameCinematic(): EndgameCinematic`
- **moddable** `newEndgameCutscene(): Cutscene` (wrap only: scripts cannot call it)
- **moddable** `updateEndgameCinematic(endg: EndgameCinematic, dt: float32)`

### `enemy`

- **moddable** `drawAttackWarning(warning: AttackWarning)`
- **moddable** `drawBossPhaseTransition(enemy: Enemy)` (wrap only: scripts cannot call it)
- **moddable** `drawChargeWindup(enemy: Enemy)`
- **moddable** `drawCustomBoss(enemy: Enemy)` (wrap only: scripts cannot call it)
- **moddable** `drawEliteAura(enemy: Enemy, gameTime: float32)`
- **moddable** `drawEliteOverlay(enemy: Enemy, gameTime: float32)`
- **moddable** `drawEnemy(enemy: Enemy)`
- **moddable** `drawLaser(laser: Laser)`
- **moddable** `drawLegionTethers(boss: Enemy, enemies: seq[Enemy])`
- **moddable** `drawMeteorWarning(impact: Vector2, source: Vector2, radius: float32, baseCol: Color, progress: float32, blastRadius: float32)`
- **moddable** `drawOmegaGlyph(cx: float32, cy: float32, r: float32, thick: float32, col: Color)` (wrap only: scripts cannot call it)
- **moddable** `drawRicochetLaserBeam(warning: AttackWarning)`
- **moddable** `drawRoyalGuardRegalia(enemy: Enemy)`
- **moddable** `drawSignatureAttackActive(warning: AttackWarning)`
- **moddable** `getEliteAuraColor(eliteType: EliteType): Color` (wrap only: scripts cannot call it)
- **moddable** `isLivingRoyalGuard(e: Enemy): bool`
- **moddable** `makeElite(enemy: Enemy, waveNumber: int, scalingWave: int, chanceScale: float32, force: bool, forcedEffects: int)`
- **moddable** `newEnemy(x: float32, y: float32, difficulty: float32, enemyType: EnemyType, game: Game): Enemy`
- **moddable** `spawnBossById(screenWidth: int32, screenHeight: int32, bossId: int, scalingWave: int): Enemy`
- **moddable** `spawnBoss(screenWidth: int32, screenHeight: int32, waveNumber: int): Enemy`
- **moddable** `updateEliteEffects(enemy: Enemy, dt: float32)`
- **moddable** `updateEnemy(enemy: var Enemy, playerPos: Vector2, dt: float32, walls: seq[Wall], currentTime: float32, game: var Game): bool`

### `enemy_config`

- **moddable** `enemyAiType(et: EnemyType): EnemyType`
- **moddable** `enemySaveName(et: EnemyType): string`
- **moddable** `enemyScriptName(et: EnemyType): string`
- **moddable** `getScaledEnemyStats(config: EnemyConfig, difficulty: float32): tuple[hp: float32, radius: float32, speed: float32, requiredHits: int]`
- **moddable** `invalidateEnemyConfigCache()`
- **moddable** `isEnemyLive(et: EnemyType): bool`
- `isModEnemy(et: EnemyType): bool`
- **moddable** `parseEnemySaveName(s: string, et: var EnemyType): bool`
- **moddable** `resetModEnemies()`
- **moddable** `resolveEnemyScriptName(s: string, et: var EnemyType): bool`
- **moddable** `vanillaEnemyConfig(enemyType: EnemyType): EnemyConfig`

### `enemy_helpers`

- **moddable** `applyEnemyInertia(enemy: var Enemy, desiredVel: Vector2, dt: float32, acceleration: float32, braking: float32): Vector2`
- **moddable** `approachVelocity(current: Vector2, target: Vector2, acceleration: float32, dt: float32): Vector2`
- **moddable** `chasePlayer(enemy: Enemy, playerPos: Vector2, dt: float32, effectiveSpeed: float32): Vector2`
- **moddable** `checkScreenBoundaryCollision(enemy: Enemy, nextPos: Vector2, game: Game, config: EnemyConfig): bool`
- **moddable** `checkScreenEntry(enemy: var Enemy, game: Game)`
- **moddable** `checkWallCollision(enemy: var Enemy, nextPos: Vector2, walls: seq[Wall], currentTime: float32, game: var Game): bool`
- **moddable** `desiredVelocityFromNext(currentPos: Vector2, desiredNextPos: Vector2, dt: float32): Vector2` (wrap only: scripts cannot call it)
- **moddable** `enemyInertiaSizeScale(enemy: Enemy): float32` (wrap only: scripts cannot call it)
- **moddable** `executeRangedAttack(enemy: var Enemy, playerPos: Vector2, game: var Game)`
- **moddable** `forceScreenEntry(enemy: Enemy, playerPos: Vector2, dt: float32, effectiveSpeed: float32, game: Game): Vector2`
- **moddable** `getSpecialFloat(data: Table[string, string], key: string, default: float32): float32`
- **moddable** `getSpecialInt(data: Table[string, string], key: string, default: int): int`
- **moddable** `maintainOptimalDistance(enemy: Enemy, playerPos: Vector2, dt: float32, effectiveSpeed: float32, config: EnemyConfig): Vector2`
- **moddable** `nextInertialEnemyPos(enemy: var Enemy, desiredNextPos: Vector2, dt: float32): Vector2`
- **moddable** `parseSpecialData(data: string): Table[string, string]`
- **moddable** `randomEdgeSpawnPos(screenWidth: int32, screenHeight: int32, margin: float32): tuple[x: float32, y: float32]`

### `engine_3d`

- **moddable** `addShake(cam: var FPSCamera, intensity: float32)`
- **moddable** `checkCollision(pos: Vector3, radius: float32, platforms: seq[Platform3D]): (bool, Platform3D)`
- **moddable** `drawArena(arena: Arena3D)`
- **moddable** `drawPlatform(platform: Platform3D)`
- **moddable** `drawProjectile(proj: Projectile3D)`
- **moddable** `effectiveRadius(proj: Projectile3D): float32`
- **moddable** `generateArena(theme: string, radius: float32): Arena3D`
- **moddable** `getForward(cam: FPSCamera): Vector3`
- **moddable** `getRight(cam: FPSCamera): Vector3`
- **moddable** `initCamera3D(pos: Vector3): FPSCamera`
- **moddable** `updateCamera(cam: var FPSCamera, mouseDelta: Vector2, sensitivity: float32)`
- **moddable** `updatePlatforms(platforms: var seq[Platform3D], dt: float32)`

### `feedback`

- `copyReport(kind: FeedbackKind, title: string, body: string, includeInfo: bool)`
- `hasContent(title: string, body: string): bool`
- `openExternalUrl(url: string)`
- `openSupportUrl(url: string)`
- `saveReport(kind: FeedbackKind, title: string, body: string, includeInfo: bool): string`
- `sendToGitHub(kind: FeedbackKind, title: string, body: string, includeInfo: bool): SendResult`

### `feedback_window`

- **moddable** `drawFeedbackWindow(fw: FeedbackWindow)`
- **moddable** `newFeedbackWindow(screenWidth: int, screenHeight: int): FeedbackWindow`
- **moddable** `resetFeedbackView(fw: FeedbackWindow)`
- **moddable** `updateFeedbackWindow(fw: FeedbackWindow, dt: float32, screenWidth: int, screenHeight: int, allWindows: openArray[OSWindow])`
- **moddable** `wantsTextInput(fw: FeedbackWindow): bool`

### `fx`

- **moddable** `drawBossDeathBlasts(blasts: seq[BossDeathBlast])`
- **moddable** `drawLightningBolts(bolts: seq[LightningBolt])`
- **moddable** `drawPathShockwaves(waves: seq[PathShockwave])`
- **moddable** `drawShockwaveRings(rings: seq[ShockwaveRing])`
- **moddable** `spawnBossDeathBlastInto(blasts: var seq[BossDeathBlast], pos: Vector2, maxRadius: float32, sourceEnemyId: int, color: Color)`
- **moddable** `spawnLightningBoltInto(bolts: var seq[LightningBolt], fromPos: Vector2, toPos: Vector2, color: Color)`
- **moddable** `spawnPathShockwaveInto(waves: var seq[PathShockwave], points: seq[Vector2], width: float32, color: Color)`
- **moddable** `spawnShockwaveRingInto(rings: var seq[ShockwaveRing], pos: Vector2, maxRadius: float32, color: Color)`
- **moddable** `updateLightningBolts(bolts: var seq[LightningBolt], dt: float32)`
- **moddable** `updatePathShockwaves(waves: var seq[PathShockwave], dt: float32)`
- **moddable** `updateShockwaveRings(rings: var seq[ShockwaveRing], dt: float32)`

### `game`

- **moddable** `addCoopPlayer(game: Game, nickname: string, skin: int, bulletSkin: int, shape: int, particleSkin: int, bulletShape: int): Player`
- **moddable** `applyCoopAction(game: var Game, slot: int32, a: CoopAction)`
- **moddable** `applyLevelUpStatBoost(game: Game)` (wrap only: scripts cannot call it)
- **moddable** `bankRunLevelUps(game: Game)` (wrap only: scripts cannot call it)
- **moddable** `beginCoopRun(game: Game)`
- **moddable** `beginDraftResume(game: var Game)`
- **moddable** `beginEnter3D(game: Game, opts: World3DOptions)` (wrap only: scripts cannot call it)
- **moddable** `bossDefeated(manager: var BossWaveManager)` (wrap only: scripts cannot call it)
- **moddable** `buyFromShop(game: var Game, row: int)`
- **moddable** `canSpawnBoss(manager: BossWaveManager): bool` (wrap only: scripts cannot call it)
- **moddable** `canStartNewWave(manager: BossWaveManager): bool` (wrap only: scripts cannot call it)
- **moddable** `cheatCompleteRogueliteFloor(game: var Game)`
- **moddable** `checkPendingLevelDraft(game: Game)` (wrap only: scripts cannot call it)
- **moddable** `chooseFloor(game: var Game, card: int)`
- **moddable** `cleanupGame(game: Game)`
- **moddable** `clearBossWave(manager: var BossWaveManager)` (wrap only: scripts cannot call it)
- **moddable** `closeShop(game: var Game)`
- **moddable** `collectPickup(game: Game, c: Consumable): bool`
- **moddable** `completeBossWave(game: Game)` (wrap only: scripts cannot call it)
- **moddable** `continueAfterDraft(game: var Game, legendaryRound: bool)`
- **moddable** `drawDeathSequenceOverlay(game: Game)`
- **moddable** `drawGameOver(game: Game)`
- **moddable** `drawGame(game: Game)`
- **moddable** `drawPlayerActor(game: Game, playerVisible: bool)`
- **moddable** `drawVictory(game: Game)`
- **moddable** `enterWorld3D(game: Game, opts: World3DOptions)`
- **moddable** `fireConfiguredEnemyShot(game: var Game, enemy: Enemy)` (wrap only: scripts cannot call it)
- **moddable** `hudInterfaceScale(): float32`
- `isBossActive(manager: BossWaveManager): bool`
- `isBossCoinActive(manager: BossWaveManager): bool`
- **moddable** `leaveShop(game: var Game)`
- **moddable** `loadShopCounts(game: Game, p: Player)`
- **moddable** `newGame(screenWidth: int32, screenHeight: int32, playerSkin: int, bulletSkin: int, playerShape: int, particleSkin: int, bulletShape: int): Game`
- **moddable** `pickDraftCard(game: var Game, index: int)`
- **moddable** `rerollDraft(game: var Game): bool`
- **moddable** `resolveBulletEnemyHit(game: var Game, bullet: Bullet, target: Enemy, echoParent: Bullet, dt: float32): bool` (wrap only: scripts cannot call it)
- **moddable** `setGameMode(game: Game, mode: GameMode)`
- **moddable** `spawnConfiguredBoss(game: Game, bossBlockWave: int, bossId: int)` (wrap only: scripts cannot call it)
- **moddable** `spawnWaveEnemies(game: Game, count: int)` (wrap only: scripts cannot call it)
- **moddable** `startSelectedTheme(game: var Game)`
- **moddable** `startWave(game: Game)`
- **moddable** `syncLocalDraftView(game: var Game)`
- **moddable** `tickBossAttacks(game: var Game, enemy: Enemy, bossDef: BossDefinition, dt: float32)` (wrap only: scripts cannot call it)
- **moddable** `updateCoopModal(game: var Game, dt: float32)`
- **moddable** `updateFloatingText(game: var Game, dt: float32)`
- **moddable** `updateGame(game: var Game, dt: float32)`
- **moddable** `updatePresentationLists(game: var Game, dt: float32)`

### `game_3d`

- **moddable** `addEntity3D(world: Game3D, e: Entity3D)` (wrap only: scripts cannot call it)
- **moddable** `allocId3D(world: Game3D): int` (wrap only: scripts cannot call it)
- **moddable** `damageBoss3D(world: Game3D, amount: float32)`
- **moddable** `damageEntity3D(world: Game3D, e: Entity3D, amount: float32): float32`
- **moddable** `damagePlayer3D(world: Game3D, amount: float32, source: string, entity: Entity3D): float32`
- **moddable** `finishWorld3D(world: Game3D, result: World3DResult)`
- **moddable** `followCamera3D(world: Game3D)`
- **moddable** `healPlayer3D(world: Game3D, amount: float32)`
- **moddable** `initGame3D(opts: World3DOptions, player2D: Player): Game3D`
- `isUp3D(p: Player3D): bool`
- **moddable** `killEntity3D(world: Game3D, e: Entity3D, credit: bool)`
- **moddable** `local3DInput(world: Game3D)`
- `localPlayer3D(world: Game3D): Player3D`
- **moddable** `nearestPlayer3D(world: Game3D, pos: Vector3): Player3D`
- **moddable** `newEntity3D(world: Game3D, tag: string): Entity3D`
- **moddable** `newPickup3D(world: Game3D, pos: Vector3, kind: string, value: float32): Pickup3D`
- **moddable** `newProjectile3D(pos: Vector3, vel: Vector3, damage: float32, fromPlayer: bool): Projectile3D`
- **moddable** `processWorld3DActions(world: Game3D)`
- **moddable** `raycast3D(world: Game3D, origin: Vector3, dir: Vector3, maxDist: float32): RayHit3D`
- **moddable** `raylibCamera(camera: FPSCamera): Camera`
- **moddable** `renderGame3D(world: Game3D)`
- **moddable** `requestFinish3D(world: Game3D, result: World3DResult)`
- **moddable** `seatPlayers3D(world: Game3D, players2D: seq[Player], coop: CoopState)`
- **moddable** `spawnDamageNumber3D(damageNumbers: var seq[DamageNumber3D], pos: Vector3, damage: float32, color: Color)`
- **moddable** `sweepDead(world: Game3D)`
- **moddable** `teamOut3D(world: Game3D): bool`
- **moddable** `tickDamageNumbers3D(world: Game3D, dt: float32)`
- **moddable** `updateGame3D(world: Game3D, dt: float32)`
- `viewTarget3D(world: Game3D): Player3D`
- **moddable** `worldToScreen3D(camera: FPSCamera, pos: Vector3): tuple[x: float32, y: float32, visible: bool]`

### `gamemode_definitions`

- **moddable** `canUseCheats(mode: GameMode): bool`
- **moddable** `getAllGameModes(): seq[GameModeDefinition]`
- **moddable** `getGameModeDefinition(mode: GameMode): GameModeDefinition`
- **moddable** `getGameModeName(mode: GameMode): string`
- **moddable** `isPvPMode(mode: GameMode): bool`
- **moddable** `isRogueliteMode(mode: GameMode): bool`
- **moddable** `isSandboxMode(mode: GameMode): bool`
- **moddable** `isTimeSurvivalMode(mode: GameMode): bool`
- **moddable** `isWaveMode(mode: GameMode): bool`
- **moddable** `shouldUseWaves(mode: GameMode): bool`

### `gamepad_input`

- `activeGamepad(): int32`
- `aimDir(): Vector2`
- `availableGamepads(): seq[tuple[index: int32, name: string]]`
- `gamepadAnyButtonPressed(): GamepadButton`
- `gamepadBindLabel(b: GamepadButton): string`
- `gamepadCursorPos(): Vector2`
- `gamepadFireDown(binds: GamepadBindings): bool`
- `gamepadNavPressed(dir: GamepadNavDir): bool`
- `getPointerWheelMove(): float32`
- `isBackPressed(): bool`
- `isGamepadActive(): bool`
- `isGamepadBackDown(): bool`
- `isGamepadBindDown(binds: GamepadBindings, action: KeyAction): bool`
- `isGamepadBindPressed(binds: GamepadBindings, action: KeyAction): bool`
- `isGamepadBindReleased(binds: GamepadBindings, action: KeyAction): bool`
- `isGamepadConfirmDown(): bool`
- `isGamepadConfirmPressed(): bool`
- `isGamepadStartPressed(): bool`
- `isPointerDown(): bool`
- `isPointerPressed(): bool`
- `isPointerReleased(): bool`
- `keyboardKeyLabel(k: KeyboardKey): string`
- `leftStick(): Vector2`
- `preferredGamepad(): int32`
- `rightStick(): Vector2`
- `setGamepadAimPoint(pos: Vector2)`
- `setGamepadCursorMode(mode: GamepadCursorMode)`
- `setPreferredGamepad(idx: int32)`
- `suppressBackThisFrame()`
- `updateGamepadInput(dt: float32, virtualWidth: float32, virtualHeight: float32, realMouseVirtualPos: Vector2)`

### `hardware_info`

- `getHardwareInfo(): HardwareInfo`

### `help_window`

- **moddable** `addOutput(help: HelpWindow, text: string, color: Color, icon: int, indent: int)` (wrap only: scripts cannot call it)
- **moddable** `bottomScrollOffset(help: HelpWindow): int` (wrap only: scripts cannot call it)
- **moddable** `drawHelpWindow(help: HelpWindow)`
- **moddable** `executeCommand(help: HelpWindow, cmd: string)` (wrap only: scripts cannot call it)
- **moddable** `getHelpCommands(): seq[HelpCommand]` (wrap only: scripts cannot call it)
- **moddable** `newHelpWindow(screenWidth: int, screenHeight: int): HelpWindow`
- **moddable** `updateHelpWindow(help: HelpWindow, dt: float32, screenWidth: int, screenHeight: int, allWindows: openArray[OSWindow]): int`
- **moddable** `wantsTextInput(help: HelpWindow): bool`

### `hud_dock`

- **moddable** `drawDockBands(time: float32)`
- **moddable** `drawDockBar(x: int32, y: int32, w: int32, h: int32, frac: float32, fill: Color, rim: Color)`
- **moddable** `drawDockCard(x: int32, y: int32, w: int32, h: int32, accent: Color, bg: Color)`
- **moddable** `drawDockHeader(x: int32, y: int32, w: int32, title: string, accent: Color, right: string, rightColor: Color): int32`
- **moddable** `drawOverlayText(text: string, x: int32, y: int32, size: int32, color: Color)`
- **moddable** `drawShadowText(text: string, x: int32, y: int32, size: int32, color: Color)`
- **moddable** `hudSurface(c: Color): Color`
- **moddable** `textShadow(alpha: uint8): Color`

### `icon_drawing`

- **moddable** `drawCurrencyIcon(cx: int32, cy: int32, size: int32, iconType: CurrencyIconType, alpha: uint8)`
- **moddable** `drawLockIcon(x: int32, y: int32, size: int32, color: Color)`
- **moddable** `drawPatchIcon(x: int32, y: int32, size: int32, patch: RogueliteRelicType, color: Color)`
- `drawPatchIcon(x: int32, y: int32, size: int32, patch: RogueliteRelicType, color: Color)`
- **moddable** `drawPatchIcon(x: int32, y: int32, size: int32, relic: RogueliteRelic, color: Color)`
- `drawPatchIcon(x: int32, y: int32, size: int32, relic: RogueliteRelic, color: Color)`
- **moddable** `drawPowerUpIcon(x: int32, y: int32, size: int32, powerType: PowerUpType, color: Color)`
- **moddable** `drawRoomRewardIcon(x: int32, y: int32, size: int32, reward: RoomReward, color: Color)`
- **moddable** `drawServiceIcon(x: int32, y: int32, size: int32, color: Color)`
- **moddable** `drawShopIconTile(x: int32, y: int32, size: int32, itemIndex: int, enabled: bool, selected: bool)`
- **moddable** `drawShopIcon(x: int32, y: int32, size: int32, itemIndex: int, color: Color)`
- **moddable** `shopIconAccent(itemIndex: int): Color` (wrap only: scripts cannot call it)

### `input_intent`

- `beginIntentFrame(it: var PlayerIntent)`
- **moddable** `captureLocalIntent(p: Player)`
- `consumeEdge(p: Player, e: IntentEdge): bool`
- `edgePending(p: Player, e: IntentEdge): bool`
- **moddable** `idleIntent(p: Player)`
- `pressEdge(it: var PlayerIntent, e: IntentEdge)`

### `language_select`

- **moddable** `drawLanguageSelect(screenWidth: int32, screenHeight: int32, time: float32, mousePos: Vector2, modLanguageNames: seq[string])`
- **moddable** `languageOptionRects(screenWidth: int32, screenHeight: int32): array[0 .. 1, Rectangle]`
- **moddable** `modLanguageOptionRects(screenWidth: int32, screenHeight: int32, count: int): seq[Rectangle]`

### `loading_screen`

- **moddable** `draw(screen: LoadingScreen, screenWidth: int32, screenHeight: int32)`
- **moddable** `newLoadingScreen(): LoadingScreen`
- **moddable** `setAssetCounts(screen: LoadingScreen, done: int, total: int)`
- **moddable** `setProgress(screen: LoadingScreen, progress: float32, message: string)`
- **moddable** `setStage(screen: LoadingScreen, stage: LoadingStage)`
- **moddable** `update(screen: LoadingScreen, dt: float32)`

### `localization`

- **moddable** `addModLanguage(id: string, name: string, base: Language)`
- **moddable** `builtinText(lang: Language, key: string): string`
- **moddable** `clearModLanguages()`
- **moddable** `clearModTranslations()`
- **moddable** `getLanguageName(lang: Language): string`
- **moddable** `getLanguage(): Language`
- **moddable** `languageDisplayName(setting: string): string`
- **moddable** `languageSetting(): string`
- **moddable** `missingTranslations(): seq[string]`
- **moddable** `modLanguageIndex(id: string): int`
- **moddable** `modLanguageText(english: string): string` (wrap only: scripts cannot call it)
- **moddable** `nextLanguageSetting(setting: string): string`
- **moddable** `pickText(en: string, es: string): string`
- **moddable** `setLanguage(lang: Language)`
- **moddable** `setModLanguageString(id: string, key: string, value: string)`
- **moddable** `setModLanguageText(id: string, english: string, value: string)`
- **moddable** `setModTranslation(lang: Language, key: string, value: string)`
- **moddable** `t(key: TranslationKey): string`
- **moddable** `t(key: string): string`
- **moddable** `useLanguage(setting: string): bool`

### `lore_cinematic`

- **moddable** `drawLoreCinematic(lore: LoreCinematic, screenWidth: int, screenHeight: int)`
- `newLoreCinematic(): LoreCinematic`
- **moddable** `newLoreCutscene(): Cutscene` (wrap only: scripts cannot call it)
- **moddable** `updateLoreCinematic(lore: LoreCinematic, dt: float32)`

### `mod_app_window`

- **moddable** `drawModAppWindow(mw: ModAppWindow, allWindows: openArray[OSWindow])`
- **moddable** `newModAppWindow(key: string, screenWidth: int, screenHeight: int): ModAppWindow`
- **moddable** `updateModAppWindow(mw: ModAppWindow, dt: float32, screenWidth: int, screenHeight: int, allWindows: openArray[OSWindow])`

### `mode_boss_attacks`

- **moddable** `executeModeBossAttack(game: var Game, boss: Enemy, attack: BossAttack, phase: BossPhaseDefinition)`
- **moddable** `isModeBossAttack(specialData: string): bool`
- **moddable** `retireModeBossHazards(game: var Game, boss: Enemy)`

### `mode_enemies`

- **moddable** `isBallistic(enemy: Enemy): bool`
- **moddable** `modeEnemyDamageTakenMult(enemy: Enemy, hitFrom: Vector2): float32`
- **moddable** `updateModeEnemy(enemy: var Enemy, playerPos: Vector2, dt: float32, effectiveSpeed: float32, walls: seq[Wall], currentTime: float32, game: var Game)`

### `mode_hazards`

- **moddable** `echoCapacity(): int`
- **moddable** `lkgDoorRect(door: int, screenW: float32, screenH: float32): tuple[x: float32, y: float32, w: float32, h: float32]`
- **moddable** `lkgInDoor(door: int, p: Vector2, screenW: float32, screenH: float32): bool`
- **moddable** `lkgPurgeRadius(w: AttackWarning): float32`
- **moddable** `packetLinkLength(w: AttackWarning): float32`
- **moddable** `packetTrain(w: AttackWarning): tuple[live: bool, tail: Vector2, head: Vector2]`
- **moddable** `pointSegmentDistance(p: Vector2, a: Vector2, b: Vector2): float32`
- **moddable** `portGuardBlocks(enemy: Enemy, hitFrom: Vector2): bool`
- **moddable** `rayWallDistance(origin: Vector2, dir: Vector2, maxLen: float32, walls: seq[Wall]): float32`
- **moddable** `safeModeBubble(w: AttackWarning): tuple[center: Vector2, radius: float32]`
- **moddable** `safeModeFlooding(w: AttackWarning): bool`
- **moddable** `safeModeProgress(w: AttackWarning): float32` (wrap only: scripts cannot call it)
- **moddable** `searchlightAngle(w: AttackWarning, beam: int): float32`
- **moddable** `searchlightLive(w: AttackWarning): bool`
- **moddable** `warningAge(w: AttackWarning): float32`

### `mode_intros`

- **moddable** `newPvPIntroCutscene(): Cutscene`
- **moddable** `newRogueliteIntroCutscene(): Cutscene`
- **moddable** `newSandboxIntroCutscene(): Cutscene`
- **moddable** `newSurvivalIntroCutscene(): Cutscene`
- **moddable** `newWaveIntroCutscene(): Cutscene`

### `mode_mechanics`

- **moddable** `hazardHitPlayer(game: var Game, damage: float32, cause: DeathCause, dmgType: DamageType, source: Enemy, sourceType: EnemyType, interval: float32): bool` (wrap only: scripts cannot call it)
- **moddable** `onModeEnemyKilled(game: var Game, enemy: Enemy)`
- **moddable** `pageInQuietly(game: var Game, w: AttackWarning)`
- **moddable** `recordPlayerEcho(game: var Game, aimDir: Vector2, firing: bool, dt: float32)`
- **moddable** `resetModeCombat(game: var Game)`
- **moddable** `resolveModeWarning(game: var Game, w: AttackWarning, dt: float32)`
- **moddable** `updateModeMechanics(game: var Game, dt: float32)`

### `mode_visuals`

- **moddable** `drawEnemyTethers(enemies: seq[Enemy])`
- **moddable** `drawHusks(husks: seq[HuskRecord])`
- **moddable** `drawModeBossBody(enemy: Enemy)`
- **moddable** `drawModeEnemy(enemy: Enemy)`
- **moddable** `drawModeWarningActive(w: AttackWarning)`
- **moddable** `drawModeWarningTelegraph(w: AttackWarning)`

### `mods_window`

- **moddable** `drawModsWindow(mw: ModsWindow)`
- **moddable** `newModsWindow(screenWidth: int, screenHeight: int, settings: Settings): ModsWindow`
- **moddable** `pollMarketplace(mw: ModsWindow): seq[string]`
- **moddable** `refreshModsWindow(mw: ModsWindow)`
- **moddable** `resetModsWindow(mw: ModsWindow)`
- **moddable** `updateModsWindow(mw: ModsWindow, dt: float32, screenWidth: int, screenHeight: int, allWindows: openArray[OSWindow])`
- **moddable** `wantsTextInput(mw: ModsWindow): bool`

### `orbitals`

- **moddable** `updateOrbitalWeapons(game: var Game, dt: float32)`

### `os_background`

- `arenaField(bg: OSBackgroundState): BossArenaField`
- **moddable** `drawArenaFloor(screenWidth: int32, screenHeight: int32, time: float32, accent: Color, tinted: bool, alert: float32)`
- **moddable** `drawOSBackground(bg: OSBackgroundState, screenWidth: int32, screenHeight: int32, showArenaVignette: bool, accentOverride: Color)`
- **moddable** `getBossArenaCombatBonus(bg: OSBackgroundState): tuple[damageMult: float32, fireRateMult: float32]`
- `loadArenaField(bg: var OSBackgroundState, field: BossArenaField)`
- `loadArenaSeat(bg: var OSBackgroundState, seat: BossArenaSeat)`
- **moddable** `newOSBackground(): OSBackgroundState`
- **moddable** `spawnWavePulse(bg: var OSBackgroundState, cx: float32, cy: float32, color: Color)`
- `storeArenaSeat(bg: OSBackgroundState, seat: var BossArenaSeat)`
- **moddable** `updateBossArenaField(bg: var OSBackgroundState, dt: float32, playerPos: Vector2, playerRadius: float32, screenWidth: int32, screenHeight: int32, bossActive: bool, currentWave: int): tuple[damageTriggered: bool, damage: float32]`
- **moddable** `updateOSBackground(bg: var OSBackgroundState, dt: float32, playerHP: float32, maxHP: float32, bossActive: bool, screenWidth: int32, screenHeight: int32)`

### `os_combined_hud`

- **moddable** `drawCombinedHUDPanel(game: Game, x: int32, y: int32)`
- **moddable** `drawControlsDockCard(game: Game, x: int32, bottom: int32): int32`
- **moddable** `drawControlsStrip(game: Game, centerX: int32, y: int32)`
- **moddable** `drawPatchDockCard(game: Game, x: int32, y: int32, bottom: int32, floorBottom: int32): int32`
- **moddable** `drawPlayerDock(game: Game, x: int32, top: int32, bottom: int32)`
- **moddable** `drawRogueliteDockCard(game: Game, x: int32, y: int32): int32`
- **moddable** `drawWaveDockCard(game: Game, x: int32, y: int32): int32`
- **moddable** `statusCardHeight(game: Game): int32`

### `os_debug_panel`

- **moddable** `debugPanelHeight(game: Game): int32`
- **moddable** `drawDebugPanel(game: Game, x: int32, y: int32, anchorLeftDefault: bool, docked: bool)`
- **moddable** `drawLegendaryPowerUpsPanel(game: Game, screenWidth: int32, screenHeight: int32, alignRightGutter: bool, docked: bool)`
- **moddable** `legendaryPanelHeight(game: Game, alignRightGutter: bool, docked: bool): int32`

### `os_desktop`

- **moddable** `drawCknWallpaper(w: float32, h: float32, t: float32, desktop: OSDesktop)`
- **moddable** `drawDesktopIcon(icon: DesktopIcon, time: float32, selected: bool)`
- **moddable** `drawDesktopToastsOverlay(desktop: OSDesktop, screenWidth: int32, screenHeight: int32)`
- **moddable** `drawDesktopWallpaper(screenWidth: int, screenHeight: int, time: float32, cubeRotX: float32, cubeRotY: float32, cubeRotZ: float32, cubeOffsetX: float32, cubeOffsetY: float32, modCube: bool)`
- **moddable** `drawLoadingOverlay(desktop: OSDesktop, screenWidth: int, screenHeight: int)`
- **moddable** `drawOSDesktop(desktop: OSDesktop, screenWidth: int, screenHeight: int)`
- **moddable** `drawThemeWallpaper(th: UiTheme, w: float32, h: float32, time: float32, desktop: OSDesktop)`
- **moddable** `handleDesktopInput(desktop: OSDesktop, game: Game): int`
- **moddable** `layoutDesktopIcons(desktop: OSDesktop, screenWidth: int, screenHeight: int)`
- **moddable** `newOSDesktop(): OSDesktop`
- **moddable** `showDesktopToast(desktop: OSDesktop, text: string)`
- `showDesktopToast(desktop: OSDesktop, text: string)`
- **moddable** `startLoadingAnimation(desktop: OSDesktop, text: string)`
- **moddable** `tickDesktopToasts(desktop: OSDesktop, dt: float32)`
- **moddable** `updateOSDesktop(desktop: OSDesktop, dt: float32, mouseOverWindow: bool, screenWidth: int, screenHeight: int)`

### `os_enemy_labels`

- **moddable** `drawEnemyLabel(enemy: Enemy, showHealthBar: bool, enabled: bool)`
- **moddable** `drawEnemyWarningIndicator(enemy: Enemy)`
- **moddable** `getEnemyProcessName(enemy: Enemy): string`

### `os_legacy_hud`

- **moddable** `drawLegacyBorderPanel(game: Game)`
- **moddable** `drawLegacyStatusPanel(game: Game, x: int32, y: int32)`

### `os_powerup_installer`

- **moddable** `cardRect(l: InstallerLayout, i: int): Rectangle`
- **moddable** `cardX(l: InstallerLayout, i: int): int32`
- **moddable** `closeRect(l: InstallerLayout): Rectangle`
- **moddable** `continueRect(l: InstallerLayout): Rectangle`
- **moddable** `drawOSPowerUpInstaller(game: Game)`
- **moddable** `drawPowerUpInstallerExhausted(game: Game)`
- **moddable** `installerLayout(): InstallerLayout`
- **moddable** `rerollRect(l: InstallerLayout): Rectangle`

### `os_roguelite`

- **moddable** `drawHeatPanel(game: Game, x: int32, y: int32, w: int32, h: int32)`
- **moddable** `drawKitCard(game: Game, kit: RogueliteStarterKit, x: int32, y: int32, selected: bool, hovered: bool)`
- **moddable** `drawPanel(x: int32, y: int32, w: int32, h: int32, title: string, stockColor: Color, closeHovered: bool, omitTitleBar: bool)`
- **moddable** `drawRogueliteFloorSelect(game: Game)`
- **moddable** `drawRogueliteVictory(game: Game)`
- **moddable** `drawSmallButton(x: int32, y: int32, w: int32, h: int32, label: string, active: bool, stockColor: Color, hovered: bool)`
- **moddable** `drawStatChip(x: int32, y: int32, w: int32, h: int32, label: string, value: string, stockColor: Color, icon: CurrencyIconType)`
- **moddable** `finalBossCardRect(screenWidth: int32, screenHeight: int32): Rectangle`
- **moddable** `rogueliteCloseButtonRect(screenWidth: int32, screenHeight: int32): Rectangle`
- **moddable** `roguelitePanelRect(screenWidth: int32, screenHeight: int32): Rectangle` (wrap only: scripts cannot call it)
- **moddable** `rogueliteVictoryButtonRects(screenWidth: int32, screenHeight: int32): tuple[continueBtn: Rectangle, cashOut: Rectangle]`

### `os_shop`

- **moddable** `applyShopPurchaseEffect(game: Game, index: int, purchaseNumber: int, healHealth: bool)`
- **moddable** `buyRect(l: ShopLayout): Rectangle`
- **moddable** `buyShopItem(game: Game, index: int)`
- **moddable** `closeRect(l: ShopLayout): Rectangle`
- **moddable** `drawShop(game: Game)`
- **moddable** `getCurrentCost(item: ShopItem): int` (wrap only: scripts cannot call it)
- **moddable** `initShopItems(): array[0 .. 5, ShopItem]`
- **moddable** `itemRect(l: ShopLayout, i: int, scroll: int32): Rectangle`
- **moddable** `keepShopSelectionVisible(game: Game)`
- **moddable** `listHeight(l: ShopLayout): int32` (wrap only: scripts cannot call it)
- **moddable** `listRect(l: ShopLayout): Rectangle`
- **moddable** `sandboxWaveAverageConfig(base: SandboxConfig, wave: int): SandboxConfig`
- **moddable** `shopDamageGain(purchaseNumber: int): float32` (wrap only: scripts cannot call it)
- **moddable** `shopHealthGain(purchaseNumber: int): int` (wrap only: scripts cannot call it)
- **moddable** `shopLayout(): ShopLayout`
- **moddable** `shopRowCount(game: Game): int`

### `os_splash`

- **moddable** `drawSplashScreen(splash: SplashScreen, screenWidth: int, screenHeight: int)`
- **moddable** `fastForwardSplash(splash: SplashScreen)`
- **moddable** `newSplashScreen(): SplashScreen`
- **moddable** `updateSplashScreen(splash: SplashScreen, dt: float32)`

### `os_system_screens`

- **moddable** `drawSystemCrash(game: Game, selectedButton: int, showContinue: bool, continueAt: int, livesUsed: int, continueLabel: string)`
- **moddable** `drawSystemSecured(game: Game, selectedButton: int)`

### `os_task_manager`

- **moddable** `drawOSTaskManager(game: Game, selectedTab: TaskManagerTab): tuple[resumeClicked: bool, settingsClicked: bool, exitClicked: bool,
      newTab: TaskManagerTab]`
- **moddable** `drawQuitConfirmDialog(game: Game, runEnds: bool): tuple[confirmed: bool, cancelled: bool]`
- **moddable** `isMouseOverRect(mousePos: Vector2, x: int32, y: int32, width: int32, height: int32): bool` (wrap only: scripts cannot call it)
- **moddable** `stepTaskManagerTab(game: Game, current: TaskManagerTab, step: int): TaskManagerTab`
- **moddable** `taskManagerTabs(game: Game): seq[TaskManagerTab]` (wrap only: scripts cannot call it)

### `os_window`

- **moddable** `bringWindowToFront(window: OSWindow, allWindows: openArray[OSWindow])` (wrap only: scripts cannot call it)
- **moddable** `drawResizeIndicator(window: OSWindow)`
- **moddable** `drawWindowChrome(window: OSWindow)`
- **moddable** `getResizeEdge(window: OSWindow, mouseX: float32, mouseY: float32): int` (wrap only: scripts cannot call it)
- **moddable** `handleOSWindowInput(window: OSWindow, screenWidth: int, screenHeight: int, allWindows: openArray[OSWindow]): bool`
- **moddable** `hasKeyboard(window: OSWindow): bool`
- **moddable** `isPointInCloseButton(window: OSWindow, mouseX: float32, mouseY: float32): bool` (wrap only: scripts cannot call it)
- **moddable** `isPointInMinimizeButton(window: OSWindow, mouseX: float32, mouseY: float32): bool` (wrap only: scripts cannot call it)
- **moddable** `isPointInTitleBar(window: OSWindow, mouseX: float32, mouseY: float32): bool` (wrap only: scripts cannot call it)
- **moddable** `isPointInWindow(window: OSWindow, mouseX: float32, mouseY: float32): bool`
- **moddable** `isWindowTopmostAtPoint(window: OSWindow, mouseX: float32, mouseY: float32, allWindows: openArray[OSWindow]): bool`
- **moddable** `newOSWindow(title: string, x: int, y: int, width: int, height: int, iconColor: Color, resizable: bool): OSWindow`
- **moddable** `startMinimizeAnimation(window: OSWindow)` (wrap only: scripts cannot call it)
- **moddable** `startRestoreAnimation(window: OSWindow)` (wrap only: scripts cannot call it)
- **moddable** `uiScaleOfWindow(window: OSWindow): float32`
- **moddable** `updateOSWindow(window: OSWindow, dt: float32)`

### `particle`

- **moddable** `drawCurrencyIndicator(indicator: CurrencyIndicator)`
- **moddable** `drawDamageNumber(dmgNum: DamageNumber, scale: float32)`
- **moddable** `drawPerkIndicator(indicator: PerkIndicator)`
- **moddable** `newCurrencyIndicator(x: float32, y: float32, amount: int, kind: CurrencyIndicatorKind): CurrencyIndicator`
- **moddable** `newDamageNumber(x: float32, y: float32, damage: float32, fromPlayer: bool, isCritical: bool, damageType: DamageType): DamageNumber`
- **moddable** `newPerkIndicator(x: float32, y: float32, text: string, color: Color): PerkIndicator`
- **moddable** `updateCurrencyIndicator(indicator: CurrencyIndicator, dt: float32): bool`
- **moddable** `updateDamageNumber(dmgNum: DamageNumber, dt: float32): bool`
- **moddable** `updatePerkIndicator(indicator: PerkIndicator, dt: float32): bool`

### `particle_pool`

- `acquireParticleDetailed(pool: ParticlePool, x: float32, y: float32, velX: float32, velY: float32, color: Color, lifetime: float32, startSize: float32, endSize: float32, drag: float32, gravity: float32, glow: float32, style: ParticleStyle, layer: ParticleLayer, rotation: float32, spin: float32): bool`
- `drawParticlePoolLayer(pool: ParticlePool, layer: ParticleLayer)`
- `drawParticlePoolLayer(pool: ParticlePool, layer: ParticleLayer, screenWidth: float32, screenHeight: float32)`
- `newParticlePool(initialCapacity: int): ParticlePool`
- `scaledParticleBurstCount(pool: ParticlePool, requestedCount: int): int`
- `spawnEnemyDeathBurst(pool: ParticlePool, x: float32, y: float32, enemyColor: Color, enemyRadius: float32, isBoss: bool)`
- `spawnExplosionPooled(pool: ParticlePool, x: float32, y: float32, color: Color, count: int)`
- `spawnExplosiveRingPooled(pool: ParticlePool, x: float32, y: float32, radius: float32, ringCount: int, color: Color)`
- `spawnNovaExplosionPooled(pool: ParticlePool, x: float32, y: float32, radius: float32, primaryColor: Color, secondaryColor: Color)`
- `spawnShockwavePooled(pool: ParticlePool, x: float32, y: float32, radius: float32)`
- `spawnSpiralExplosionPooled(pool: ParticlePool, x: float32, y: float32, radius: float32, armCount: int, color: Color)`
- `spawnTimedParticlesAroundPooled(pool: ParticlePool, centerX: float32, centerY: float32, maxRadius: float32, rate: float32, color: Color, count: int, dt: float32, offsetY: float32)`
- `spawnTimedParticlesPooled(pool: ParticlePool, x: float32, y: float32, rate: float32, color: Color, count: int, dt: float32)`
- `spawnTrailParticlePooled(pool: ParticlePool, x: float32, y: float32, color: Color, count: int)`
- `updateParticlePool(pool: ParticlePool, dt: float32)`

### `particle_skins`

- `getParticleSkinColors(skinType: ParticleSkinType, time: float32): tuple[primary: Color, secondary: Color]`
- `getParticleSkinData(skinType: ParticleSkinType): ParticleSkinData`
- `initializeParticleSkins()`
- `spawnShootingParticles(pool: ParticlePool, x: float32, y: float32, direction: Vector2, skinType: ParticleSkinType, time: float32)`

### `patches`

- **moddable** `hasPatch(player: Player, p: RogueliteRelicType): bool`
- **moddable** `patchAccent(p: RogueliteRelicType): Color`
- **moddable** `patchAccent(r: RogueliteRelic): Color`
- **moddable** `patchCategoryAccent(c: PatchCategory): Color` (wrap only: scripts cannot call it)
- **moddable** `patchCategoryName(c: PatchCategory): string`
- **moddable** `patchCategory(p: RogueliteRelicType): PatchCategory`
- **moddable** `patchDescription(p: RogueliteRelicType): string`
- **moddable** `patchDescription(r: RogueliteRelic): string`
- **moddable** `patchKbLabel(p: RogueliteRelicType): string`
- **moddable** `patchKbLabel(r: RogueliteRelic): string`
- **moddable** `patchKbNumber(p: RogueliteRelicType): int` (wrap only: scripts cannot call it)
- **moddable** `patchName(p: RogueliteRelicType): string`
- **moddable** `patchName(r: RogueliteRelic): string`
- **moddable** `patchPrice(player: Player, base: int): int`
- **moddable** `patchSpent(game: Game, p: RogueliteRelicType): bool`
- **moddable** `patchStatusColor(s: PatchStatus): Color`
- **moddable** `patchStatusLabel(s: PatchStatus): string`
- **moddable** `patchStatus(game: Game, p: RogueliteRelicType): PatchStatus`

### `pickup`

- **moddable** `clampLootPosition(x: float32, y: float32, screenWidth: int32, screenHeight: int32): tuple[x: float32, y: float32]`
- **moddable** `magnetPullsAll(player: Player): bool`
- **moddable** `pullTowardPlayer(pos: var Vector2, playerPos: Vector2, dt: float32)`

### `player`

- **moddable** `advancePlayer(player: Player, dt: float32, screenWidth: int32, screenHeight: int32, walls: seq[Wall])`
- **moddable** `dashBurstOf(p: Player): float32`
- **moddable** `dashRechargeOf(p: Player): float32`
- **moddable** `dashTimeOf(p: Player): float32` (wrap only: scripts cannot call it)
- **moddable** `dataHarvestRangeMult(player: Player): float32` (wrap only: scripts cannot call it)
- **moddable** `drawPlayer(player: Player)`
- **moddable** `hasAnyOrbPowerUp(player: Player): bool`
- **moddable** `heal(player: Player, amount: float32): float32`
- **moddable** `newPlayer(x: float32, y: float32): Player`
- **moddable** `steerPlayer(player: Player, dt: float32, dashNow: bool)`
- **moddable** `takeDamage(player: Player, damage: float32): bool`
- **moddable** `updatePlayer(player: Player, dt: float32, screenWidth: int32, screenHeight: int32, walls: seq[Wall])`

### `player_3d`

- `applyAim3D(p: Player3D)`
- **moddable** `capture3DIntent(p: Player3D, cam: var FPSCamera, sensitivity: float32)`
- **moddable** `fireWeapon(player: Player3D, camera: FPSCamera, projectiles: var seq[Projectile3D]): bool`
- **moddable** `newPlayer3D(startPos: Vector3, health2D: float32, slot: int32): Player3D`
- **moddable** `newWeapon3D(): Weapon3D` (wrap only: scripts cannot call it)
- **moddable** `reload(player: Player3D)`
- `take3D(p: Player3D, e: IntentEdge): bool`
- **moddable** `updatePlayer(player: Player3D, arena: Arena3D, dt: float32): bool`
- **moddable** `updateWeapon(player: Player3D, dt: float32)`
- `viewOf(p: Player3D): FPSCamera`
- **moddable** `weaponReady(player: Player3D): bool`

### `post_fx`

- **moddable** `composeToTexture(level: PostFxLevel, frame: Texture2D): ptr Texture2D` (the result is a ptr Texture2D)
- **moddable** `drawComposited(level: PostFxLevel, frame: Texture2D, source: Rectangle, dest: Rectangle)`
- **moddable** `postFxEnabled(level: PostFxLevel): bool`
- **moddable** `preparePostFx(frame: Texture2D, virtualW: int32, virtualH: int32)`

### `powerup`

- **moddable** `applyPowerUp(player: Player, powerUp: PowerUp)`
- **moddable** `attemptRerollPowerUps(game: Game): bool`
- **moddable** `bulwarkDamageBonus(player: Player): float32`
- **moddable** `bulwarkMaxBonus(level: int): float32` (wrap only: scripts cannot call it)
- **moddable** `createElementalOrbs(player: Player, elementType: ElementType, level: int)` (wrap only: scripts cannot call it)
- **moddable** `createRotatingOrbs(player: Player, level: int)` (wrap only: scripts cannot call it)
- **moddable** `drawPowerUpSelectionExhausted(game: Game)`
- **moddable** `drawPowerUpSelection(game: Game)`
- **moddable** `firstRerollCost(player: Player): int`
- **moddable** `generatePowerUpChoices(player: Player, isLegendary: bool, allowedPowerFamilies: set[RoguelitePowerFamily], mode: GameMode): array[0 .. 2, PowerUp]`
- **moddable** `getElementColor(elementType: ElementType): Color`
- **moddable** `getElementDamage(level: int): float32`
- **moddable** `getFortifiedMaxHpBonus(level: int): float32` (wrap only: scripts cannot call it)
- **moddable** `getHeavyRoundsSizeMultiplier(level: int): float32`
- **moddable** `getOrbRingRadius(player: Player, level: int): float32` (wrap only: scripts cannot call it)
- **moddable** `getPowerUpLevel(player: Player, powerType: PowerUpType): int`
- **moddable** `hasPowerUp(player: Player, powerType: PowerUpType): bool`
- **moddable** `initPowerUpRollAnimation(game: Game)`
- **moddable** `initializeRerollCost(game: Game)`
- **moddable** `isOfferable(player: Player, pt: PowerUpType, allowed: set[RoguelitePowerFamily], mode: GameMode): bool`
- **moddable** `isPowerUpPoolExhausted(player: Player, isLegendary: bool, allowedPowerFamilies: set[RoguelitePowerFamily], mode: GameMode): bool`
- **moddable** `juggernautDamageBonus(player: Player): float32`
- **moddable** `juggernautInvestedHp(player: Player): float32` (wrap only: scripts cannot call it)
- **moddable** `juggernautSpeedMult(player: Player): float32`
- **moddable** `redistributeAllOrbs(player: Player)`
- **moddable** `rerollCostAfter(player: Player, cost: int): int`
- **moddable** `rotatingShieldHealth(level: int): float32` (wrap only: scripts cannot call it)
- **moddable** `rotatingShieldRegenDelay(level: int): float32` (wrap only: scripts cannot call it)
- **moddable** `skipPowerUpRollAnimation(game: Game)`
- **moddable** `updatePowerUpRollAnimation(game: Game, deltaTime: float32)`

### `powerup_data`

- **moddable** `abilityCooldown(player: Player, pt: PowerUpType): float32`
- **moddable** `abilityReady(player: Player, pt: PowerUpType): bool`
- **moddable** `getPowerUpColor(pt: PowerUpType): Color`
- **moddable** `getPowerUpDescription(powerType: PowerUpType, level: int, playerDamage: float32): string`
- **moddable** `getPowerUpMaxLevel(pt: PowerUpType): int`
- **moddable** `getPowerUpName(powerType: PowerUpType): string`
- `isModPowerUp(pt: PowerUpType): bool`
- **moddable** `isPowerUpLive(pt: PowerUpType): bool`
- **moddable** `livePowerUps(): seq[PowerUpType]`
- **moddable** `parsePowerUpSaveName(s: string, pt: var PowerUpType): bool`
- `powerUpDef(pt: PowerUpType): PowerUpDef`
- **moddable** `powerUpSaveName(pt: PowerUpType): string`
- **moddable** `powerUpScriptName(pt: PowerUpType): string`
- **moddable** `rebuildPowerUpPools()`
- **moddable** `recursionDamageBonusForLevel(level: int): float32`
- **moddable** `resetPowerUpDefs()`
- **moddable** `resolvePowerUpScriptName(s: string, pt: var PowerUpType): bool`
- **moddable** `rollStopTimes(isLegendary: bool): array[0 .. 2, float32]`
- **moddable** `setPowerUpDef(pt: PowerUpType, def: PowerUpDef)`
- **moddable** `vanillaPowerUpDef(pt: PowerUpType): PowerUpDef` (wrap only: scripts cannot call it)

### `profile_select`

- **moddable** `drawProfileSelect(state: ProfileSelectState, screenWidth: int32, screenHeight: int32, time: float32, mousePos: Vector2, activeSlot: int)`
- **moddable** `newProfileSelectState(): ProfileSelectState`
- **moddable** `refreshSlots(state: ProfileSelectState)`
- **moddable** `updateProfileSelect(state: ProfileSelectState, dt: float32, mousePos: Vector2, screenWidth: int32, screenHeight: int32): int`

### `pvp_game`

- **moddable** `applyPlayerInput(pvp: PvPGameState, playerIndex: int, input: PlayerInput, dt: float32): Vector2` (wrap only: scripts cannot call it)
- **moddable** `applyPlayerNet(pvp: PvPGameState, i: int, s: PlayerStateNet, remote: bool)` (wrap only: scripts cannot call it)
- **moddable** `areTeammates(pvp: PvPGameState, playerIdx1: int, playerIdx2: int): bool` (wrap only: scripts cannot call it)
- **moddable** `assignPlayerToTeam(playerIndex: int, maxPlayers: int, teamsEnabled: bool): PvPTeam` (wrap only: scripts cannot call it)
- **moddable** `canRematch(pvp: PvPGameState): bool` (wrap only: scripts cannot call it)
- **moddable** `capturePlayerInput(pvp: PvPGameState, dt: float32): PlayerInput` (wrap only: scripts cannot call it)
- **moddable** `checkLastSideStanding(pvp: PvPGameState): bool` (wrap only: scripts cannot call it)
- **moddable** `connectedPlayerCount(pvp: PvPGameState): int` (wrap only: scripts cannot call it)
- **moddable** `connectedTeams(pvp: PvPGameState): seq[PvPTeam]` (wrap only: scripts cannot call it)
- **moddable** `disconnectPlayer(pvp: PvPGameState, playerIndex: int)` (wrap only: scripts cannot call it)
- **moddable** `drawPackageIcon(kind: PvPPackageKind, cx: float32, cy: float32, size: float32, color: Color)` (wrap only: scripts cannot call it)
- **moddable** `drawPvP(pvp: PvPGameState, uiScale: float32)`
- **moddable** `getTeamColor(team: PvPTeam): Color`
- **moddable** `getTeamName(team: PvPTeam): string`
- **moddable** `handleDisconnect(pvp: PvPGameState, disconnectedIndex: int, reason: string)` (wrap only: scripts cannot call it)
- **moddable** `handleNetworkEvents(pvp: PvPGameState)` (wrap only: scripts cannot call it)
- **moddable** `localResult(pvp: PvPGameState): int` (wrap only: scripts cannot call it)
- **moddable** `modBanner(pvp: PvPGameState, text: string, sub: string, color: Color)`
- **moddable** `modBroadcast(pvp: PvPGameState, name: string, data: string): bool`
- **moddable** `modDamage(pvp: PvPGameState, victim: int, attacker: int, amount: float32)`
- **moddable** `modFinish(pvp: PvPGameState, winnerIdx: int, team: PvPTeam, text: string)`
- **moddable** `modHeal(pvp: PvPGameState, idx: int, amount: float32)`
- **moddable** `modKill(pvp: PvPGameState, victim: int, killer: int)`
- **moddable** `modParticles(pvp: PvPGameState, x: float32, y: float32, color: Color, count: int)`
- **moddable** `modRequest(pvp: PvPGameState, name: string, data: string): bool`
- **moddable** `modSpawnBullet(pvp: PvPGameState, owner: int, pos: Vector2, vel: Vector2, damage: float32, radius: float32, life: float32, color: Color, kind: string, pierce: int): Bullet`
- **moddable** `modTeleport(pvp: PvPGameState, idx: int, pos: Vector2)`
- **moddable** `modToast(pvp: PvPGameState, text: string, color: Color)`
- **moddable** `newPvPGameState(screenWidth: int32, screenHeight: int32, isHost: bool, maxPlayers: int, connectedPlayers: seq[tuple[index: int, skinType: int, bulletSkinType: int, shapeType: int,
          particleSkinType: int, nickname: string]], teamsEnabled: bool, playerTeamAssignments: seq[int], interpolationEnabled: bool, config: PvPConfig): PvPGameState`
- **moddable** `packageBlurb(kind: PvPPackageKind): string` (wrap only: scripts cannot call it)
- **moddable** `packageColor(kind: PvPPackageKind): Color` (wrap only: scripts cannot call it)
- **moddable** `packageDuration(kind: PvPPackageKind): float32` (wrap only: scripts cannot call it)
- **moddable** `packageFromInt(value: int): PvPPackageKind` (wrap only: scripts cannot call it)
- **moddable** `packageName(kind: PvPPackageKind): string` (wrap only: scripts cannot call it)
- **moddable** `playerIndexOf(pvp: PvPGameState, p: Player): int`
- **moddable** `playerName(pvp: PvPGameState, playerIndex: int): string`
- **moddable** `portLayout(arenaW: float32, arenaH: float32): seq[tuple[pos: Vector2, isPower: bool]]` (wrap only: scripts cannot call it)
- **moddable** `pvpBulletAlive(pvp: PvPGameState, b: Bullet): bool`
- **moddable** `reconcileState(pvp: PvPGameState, serverState: NetworkGameState)` (wrap only: scripts cannot call it)
- **moddable** `resetMatchState(pvp: PvPGameState)` (wrap only: scripts cannot call it)
- **moddable** `restartMatch(pvp: PvPGameState)` (wrap only: scripts cannot call it)
- **moddable** `rollPackage(isPower: bool): PvPPackageKind` (wrap only: scripts cannot call it)
- **moddable** `startCountdown(pvp: PvPGameState)`
- **moddable** `tickPvP(pvp: PvPGameState, input: PlayerInput, dt: float32, rematchPressed: bool)` (wrap only: scripts cannot call it)
- **moddable** `updateBullets(pvp: PvPGameState, dt: float32)` (wrap only: scripts cannot call it)
- **moddable** `updatePvPClient(pvp: PvPGameState, dt: float32)` (wrap only: scripts cannot call it)
- **moddable** `updatePvPServer(pvp: PvPGameState, dt: float32)` (wrap only: scripts cannot call it)
- **moddable** `updatePvP(pvp: PvPGameState, dt: float32)`

### `pvp_window`

- **moddable** `censorIP(ip: string): string` (wrap only: scripts cannot call it)
- **moddable** `connectToGame(pvpWin: PvPWindow, ip: string, port: int, skinType: int, bulletSkinType: int, shapeType: int, particleSkinType: int, nickname: string)`
- **moddable** `drawPvPWindowContent(pvpWin: PvPWindow, contentX: int, contentY: int, contentWidth: int, contentHeight: int)`
- **moddable** `getLocalIP(): string` (wrap only: scripts cannot call it)
- **moddable** `getTeamForPlayer(playerIndex: int, numTeams: int): PvPTeam` (wrap only: scripts cannot call it)
- **moddable** `handlePvPWindowClick(pvpWin: PvPWindow, contentX: int, contentY: int, contentWidth: int, contentHeight: int): int`
- **moddable** `handlePvPWindowInput(pvpWin: PvPWindow)`
- **moddable** `newPvPWindow(screenWidth: int, screenHeight: int): PvPWindow`
- **moddable** `resetPvPWindow(pvpWin: PvPWindow)`
- **moddable** `startHosting(pvpWin: PvPWindow)`
- **moddable** `updatePvPWindow(pvpWin: PvPWindow, dt: float32, getCosmetics: proc (): tuple[skinType: int, bulletSkinType: int, shapeType: int,
               particleSkinType: int])` (parameter getCosmetics is a proc (): tuple[skinType: int, bulletSkinType: int, shapeType: int,
               particleSkinType: int])
- **moddable** `wantsTextInput(pvpWin: PvPWindow): bool`

### `render_context`

- `applyTextFilterFor(drawScale: float32)`
- `beginUIScaleMode(scale: float32)`
- `beginVirtualScissorMode(x: int32, y: int32, width: int32, height: int32)`
- `bondMouseToVirtualViewport()`
- `clampedCamCentre(zoom: float32, cx: float32, cy: float32, worldW: float32, worldH: float32): tuple[x: float32, y: float32]`
- `clearWorldCamera()`
- `clipMouseToWindowClientArea()`
- `currentVirtualScissorIsActive(): bool`
- `endUIScaleMode()`
- `endVirtualScissorMode()`
- `getActiveUIScale(): float32`
- `getCurrentVirtualScissor(): tuple[x: int32, y: int32, w: int32, h: int32]`
- `getExtraVirtualWidth(): int32`
- `getRealVirtualMousePosition(): Vector2`
- `getRenderSupersampleScale(): float32`
- `getVirtualMousePosition(): Vector2`
- `getVirtualScreenHeight(): int32`
- `getVirtualScreenWidth(): int32`
- `getWorldCamOffsetX(): float32`
- `getWorldCamOffsetY(): float32`
- `getWorldCamScale(): float32`
- `getWorldMousePosition(): Vector2`
- `getWorldViewOffsetX(): float32`
- `getWorldViewOffsetY(): float32`
- `getWorldViewScale(): float32`
- `popUIScale()`
- `pushUIScale(scale: float32)`
- `releaseMouseClip()`
- `setGamepadAimPointWorld(p: Vector2)`
- `setRenderSupersampleScale(scale: float32)`
- `setWorldCamera(zoom: float32, cx: float32, cy: float32, worldW: float32, worldH: float32)`
- `setWorldView(offsetX: float32, offsetY: float32, scale: float32)`
- `updateRenderInputTransform(scale: float32, offsetX: float32, offsetY: float32, virtualWidth: int32, virtualHeight: int32)`
- `worldToVirtual(p: Vector2): Vector2`

### `roguelite`

- **moddable** `bankMetaCurrency(shards: int, cores: int): bool`
- **moddable** `beginRogueliteRun(game: Game, profile: RogueliteProfile, starterKit: RogueliteStarterKit, heat: int)`
- **moddable** `bossCoreReward(bossTier: int): int`
- **moddable** `bossShardReward(bossTier: int): int`
- **moddable** `canAffordCosmetic(profile: RogueliteProfile, kind: CosmeticKind, index: int): bool`
- **moddable** `canAffordPack(profile: RogueliteProfile, id: CosmeticPackId): bool`
- **moddable** `commitRogueliteRunProgress(game: Game, died: bool): bool`
- `commitRogueliteRunProgress(game: Game, died: bool): bool`
- **moddable** `completeRogueliteBoss(game: Game)`
- **moddable** `cosmeticCost(kind: CosmeticKind, index: int): CosmeticCost`
- `cosmeticCount(kind: CosmeticKind): int`
- **moddable** `cosmeticId(kind: CosmeticKind, index: int): string` (wrap only: scripts cannot call it)
- **moddable** `cosmeticIsUnlocked(profile: RogueliteProfile, kind: CosmeticKind, index: int): bool`
- **moddable** `ensureBaseCosmeticUnlocks(profile: RogueliteProfile)` (wrap only: scripts cannot call it)
- **moddable** `equipRogueliteStarter(game: Game, starterKit: RogueliteStarterKit, heatRank: int, profile: RogueliteProfile)`
- **moddable** `getRogueliteProfilePath(): string` (wrap only: scripts cannot call it)
- **moddable** `hasModRelic(run: RogueliteRun, modKey: string): bool` (wrap only: scripts cannot call it)
- **moddable** `hasRelic(run: RogueliteRun, relic: RogueliteRelic): bool`
- **moddable** `hasRelic(run: RogueliteRun, relicType: RogueliteRelicType): bool`
- **moddable** `heatChallengeRank(heat: int): int`
- **moddable** `initRogueliteProfile(): RogueliteProfile` (wrap only: scripts cannot call it)
- **moddable** `installPatch(game: Game, patch: RogueliteRelicType, modKey: string): bool`
- **moddable** `installPatch(game: Game, relic: RogueliteRelic): bool`
- **moddable** `isFree(cost: CosmeticCost): bool` (wrap only: scripts cannot call it)
- **moddable** `isValidCosmeticIndex(kind: CosmeticKind, index: int): bool`
- **moddable** `jsonToRogueliteProfile(j: JsonNode): RogueliteProfile` (wrap only: scripts cannot call it)
- **moddable** `legacyUnlockRefund(j: JsonNode): tuple[shards: int, cores: int]` (wrap only: scripts cannot call it)
- **moddable** `loadRogueliteProfile(): RogueliteProfile`
- **moddable** `makeRelic(relicType: RogueliteRelicType, modKey: string): RogueliteRelic`
- **moddable** `normalizeRogueliteProfile(profile: RogueliteProfile)` (wrap only: scripts cannot call it)
- **moddable** `ownedModPatches(run: RogueliteRun): seq[string]` (wrap only: scripts cannot call it)
- **moddable** `packIsOwned(profile: RogueliteProfile, id: CosmeticPackId): bool`
- **moddable** `packMemberCount(id: CosmeticPackId): int`
- **moddable** `packOwnedCount(profile: RogueliteProfile, id: CosmeticPackId): int`
- **moddable** `packPrice(profile: RogueliteProfile, id: CosmeticPackId): CosmeticCost`
- **moddable** `packUnownedRetail(profile: RogueliteProfile, id: CosmeticPackId): CosmeticCost`
- **moddable** `purchaseCosmetic(profile: RogueliteProfile, kind: CosmeticKind, index: int): bool`
- **moddable** `purchasePack(profile: RogueliteProfile, id: CosmeticPackId): bool`
- **moddable** `resetRogueliteProfile(profile: RogueliteProfile): bool`
- **moddable** `rogueliteContinueEndless(run: RogueliteRun)`
- **moddable** `rogueliteProfileToJson(profile: RogueliteProfile): JsonNode` (wrap only: scripts cannot call it)
- **moddable** `rollPatchChoices(run: RogueliteRun, count: int, exclude: set[RogueliteRelicType], excludeKeys: seq[string]): seq[RogueliteRelic]`
- **moddable** `sanitizeEquippedCosmetics(settings: Settings, profile: RogueliteProfile): bool`
- **moddable** `saveRogueliteProfile(profile: RogueliteProfile): bool`
- `saveRogueliteProfile(profile: RogueliteProfile): bool`
- **moddable** `survivalBossCoreReward(bossNumber: int): int`
- **moddable** `survivalBossShardReward(bossNumber: int): int`
- **moddable** `survivalEventShardReward(phaseIndex: int, rogue: bool): int`
- **moddable** `survivalMinuteShardReward(minute: int): int`
- **moddable** `syncPlayerPatches(game: Game)`
- **moddable** `unownedPatches(run: RogueliteRun, exclude: set[RogueliteRelicType]): seq[RogueliteRelicType]` (wrap only: scripts cannot call it)
- **moddable** `waveClearShardReward(wave: int): int`

### `roguelite_end_cinematic`

- **moddable** `drawRogueliteEndCinematic(c: RogueliteEndCinematic, screenWidth: int, screenHeight: int)`
- `newRogueliteEndCinematic(): RogueliteEndCinematic`
- **moddable** `newRogueliteEndCutscene(): Cutscene` (wrap only: scripts cannot call it)
- **moddable** `updateRogueliteEndCinematic(c: RogueliteEndCinematic, dt: float32)`

### `roguelite_window`

- **moddable** `drawRogueliteWindow(rw: RogueliteWindow, game: Game)`
- **moddable** `newRogueliteWindow(screenWidth: int, screenHeight: int, profile: RogueliteProfile): RogueliteWindow`
- **moddable** `updateRogueliteWindow(rw: RogueliteWindow, dt: float32, allWindows: openArray[OSWindow], screenWidth: int, screenHeight: int, game: Game): RogueliteWindowResult`

### `run_save`

- **moddable** `applyBlockCheckpoint(game: Game): bool`
- **moddable** `applySavedRun(game: Game, file: string): bool`
- **moddable** `blockCheckpointExists(mode: GameMode, modMode: string): bool`
- `blockCheckpointExists(mode: GameMode, modMode: string): bool`
- **moddable** `blockCheckpointLabel(mode: GameMode, modMode: string): tuple[en: string, es: string]`
- **moddable** `blockCheckpointLivesUsed(mode: GameMode, modMode: string): int`
- **moddable** `blockCheckpointResumePoint(mode: GameMode, modMode: string): int`
- **moddable** `canContinueRun(game: Game): bool`
- **moddable** `consumeContinueLife(game: Game)`
- **moddable** `deleteBlockCheckpoint(mode: GameMode, modMode: string)`
- **moddable** `deleteRunSave(file: string)`
- **moddable** `deleteRunSave(mode: GameMode, modMode: string)`
- **moddable** `getRunSavePath(file: string): string` (wrap only: scripts cannot call it)
- **moddable** `hasBlockCheckpoint(mode: GameMode, modMode: string): bool`
- **moddable** `hasSavedRun(mode: GameMode, modMode: string): bool`
- **moddable** `invalidateBlockCheckpointCache()`
- **moddable** `markCheckpointCurrencyBanked(game: Game)`
- **moddable** `runSaveFileFor(mode: GameMode, modMode: string): string` (wrap only: scripts cannot call it)
- **moddable** `saveBlockCheckpoint(game: Game, scripted: bool, labelEn: string, labelEs: string): bool`
- **moddable** `saveRunState(game: Game, file: string, bypassStateGate: bool)`
- **moddable** `setRestorePointsUsed(game: Game, used: int)`

### `run_statistics`

- **moddable** `bookCredits(game: Game, amount: int)`
- **moddable** `calculateDerivedMetrics()`
- **moddable** `calculatePlayStyle()` (wrap only: scripts cannot call it)
- **moddable** `clearLastCompletedRun()`
- **moddable** `cloneRunStatistics(src: RunStatistics): RunStatistics` (wrap only: scripts cannot call it)
- **moddable** `endRun(player: Player, waveReached: int, finalScore: int, cheatsUsed: bool, died: bool)` (wrap only: scripts cannot call it)
- **moddable** `finalizeRunTracking(game: Game, died: bool)`
- **moddable** `gainCredits(game: Game, amount: int)`
- **moddable** `getLastRunStats(): RunStatistics`
- **moddable** `hasLastRunStats(): bool`
- **moddable** `hasValidRunStats(): bool`
- **moddable** `initCombatStats(): CombatStats`
- **moddable** `initComparisonStats(): ComparisonStats`
- **moddable** `initMovementStats(): MovementStats`
- **moddable** `initPerformanceStats(): PerformanceStats`
- **moddable** `initPowerUpStats(): PowerUpStats`
- **moddable** `initResourceStats(): ResourceStats`
- **moddable** `initRunStatistics(): RunStatistics` (wrap only: scripts cannot call it)
- **moddable** `initializeRunTracking(game: Game)`
- **moddable** `loadLastCompletedRun(loadedStats: RunStatistics)`
- **moddable** `newRunStatisticsFor(gameMode: GameMode): RunStatistics`
- **moddable** `recordCoinEarned(amount: int)` (wrap only: scripts cannot call it)
- **moddable** `recordCoinSpent(amount: int, itemName: string, gameTime: float32)` (wrap only: scripts cannot call it)
- **moddable** `recordConsumable(consumType: ConsumableType)` (wrap only: scripts cannot call it)
- **moddable** `recordDamageAvoided(amount: float32)` (wrap only: scripts cannot call it)
- **moddable** `recordDamageDealt(damage: float32)`
- **moddable** `recordDamageTaken(damage: float32, enemyType: EnemyType, gameTime: float32, playerPos: Vector2)` (wrap only: scripts cannot call it)
- **moddable** `recordKill(enemyType: EnemyType, isElite: bool, isBoss: bool, gameTime: float32, pos: Vector2)`
- **moddable** `recordLegendaryAbility(abilityType: string, gameTime: float32, playerPos: Vector2)` (wrap only: scripts cannot call it)
- **moddable** `recordNearDeath(gameTime: float32, playerPos: Vector2)` (wrap only: scripts cannot call it)
- **moddable** `recordPowerUpChosen(powerUp: PowerUp, gameTime: float32)` (wrap only: scripts cannot call it)
- **moddable** `recordPowerUpDamage(powerType: PowerUpType, damage: float32)` (wrap only: scripts cannot call it)
- **moddable** `recordPowerUpHealing(powerType: PowerUpType, restored: float32, overheal: float32)` (wrap only: scripts cannot call it)
- **moddable** `recordRerollSpent(amount: int)`
- **moddable** `recordShotFired()` (wrap only: scripts cannot call it)
- **moddable** `recordShotHit(damage: float32, enemyType: EnemyType, isCrit: bool, countsAsShot: bool)` (wrap only: scripts cannot call it)
- **moddable** `recordShotMissed()` (wrap only: scripts cannot call it)
- **moddable** `recordSpecialMechanic(mechType: string)` (wrap only: scripts cannot call it)
- **moddable** `recordWallDamaged()` (wrap only: scripts cannot call it)
- **moddable** `recordWallDestroyed(damageBlocked: float32)` (wrap only: scripts cannot call it)
- **moddable** `recordWallPlaced(gameTime: float32, pos: Vector2)` (wrap only: scripts cannot call it)
- **moddable** `recordWaveComplete(waveNumber: int, waveTime: float32, gameTime: float32)` (wrap only: scripts cannot call it)
- **moddable** `resumeRunTracking(game: Game)`
- **moddable** `saveLastCompletedRun()`
- **moddable** `startNewRun(gameMode: GameMode)` (wrap only: scripts cannot call it)
- **moddable** `takeFrameDamageDealt(): float32`
- **moddable** `trackBulletDespawn(game: Game, bullet: Bullet, hitEnemy: bool)`
- **moddable** `trackBulletFired(game: Game)`
- **moddable** `trackBulletHit(game: Game, bullet: Bullet, enemy: Enemy, damage: float32)`
- **moddable** `trackCombo(game: Game, comboCount: int)`
- **moddable** `trackConsumableHealing(game: Game, requested: float32, restored: float32)`
- **moddable** `trackConsumablePickup(game: Game, consumType: ConsumableType)`
- **moddable** `trackDamageAvoided(game: Game)`
- **moddable** `trackEnemyKilled(game: Game, enemy: Enemy)`
- **moddable** `trackHealing(game: Game, source: PowerUpType, requested: float32, restored: float32, bloodMasteryMult: float32)`
- **moddable** `trackLevelUpHealing(game: Game, requested: float32, restored: float32)`
- **moddable** `trackMovementFrame(game: Game, dt: float32)`
- **moddable** `trackPerfectWave()`
- **moddable** `trackPhaseShift(game: Game, distanceTraveled: float32)`
- **moddable** `trackPlayerDamage(game: Game, enemyType: EnemyType)`
- **moddable** `trackPowerUpDamageWithMastery(game: Game, basePower: PowerUpType, masteryPower: PowerUpType, damage: float32, masteryMult: float32)`
- **moddable** `trackPowerUpDamage(game: Game, powerType: PowerUpType, damage: float32)`
- **moddable** `trackPowerUpSelection(game: Game, powerUp: PowerUp)`
- **moddable** `trackShopPurchase(game: Game, itemName: string, cost: int)`
- **moddable** `trackTimeWarp(game: Game, duration: float32)`
- **moddable** `trackWallDamaged(game: Game)`
- **moddable** `trackWallDestruction(game: Game, damageBlocked: float32)`
- **moddable** `trackWallPlacement(game: Game, pos: Vector2)`
- **moddable** `trackWaveCompletion(game: Game, waveNumber: int, waveTime: float32)`
- **moddable** `updateDPS(damage: float32)` (wrap only: scripts cannot call it)
- **moddable** `updateMovement(player: Player, dt: float32, gameTime: float32)` (wrap only: scripts cannot call it)
- **moddable** `updateRunDuration(dt: float32)` (wrap only: scripts cannot call it)

### `sandbox`

- **moddable** `drawSandboxSidebar(game: Game, screenWidth: int32, screenHeight: int32)`
- **moddable** `handleSandboxInput(game: Game, screenWidth: int32, screenHeight: int32)`
- **moddable** `updateSandboxMode(game: Game, dt: float32)`

### `sandbox_window`

- **moddable** `applySandboxConfig(game: Game)`
- **moddable** `baseSandboxConfig(): SandboxConfig` (wrap only: scripts cannot call it)
- **moddable** `drawSandboxWindowContent(sw: SandboxWindow, cx: int32, cy: int32, cw: int32, ch: int32)` (wrap only: scripts cannot call it)
- **moddable** `drawSandboxWindow(sw: SandboxWindow)`
- **moddable** `newSandboxWindow(screenWidth: int, screenHeight: int): SandboxWindow`
- **moddable** `playerToSandboxConfig(p: Player): SandboxConfig` (wrap only: scripts cannot call it)
- **moddable** `resetSandboxWindow(sw: SandboxWindow)`
- **moddable** `updateSandboxWindow(sw: SandboxWindow, dt: float32, allWindows: openArray[OSWindow], screenWidth: int, screenHeight: int): SandboxWindowResult`

### `save_system`

- **moddable** `createProfile(slot: int, difficulty: GameDifficulty): bool`
- **moddable** `deleteLastRunStats(): bool`
- **moddable** `deleteProfile(slot: int): bool`
- **moddable** `getAppDataPath(): string`
- **moddable** `getLastRunStatsPath(): string` (wrap only: scripts cannot call it)
- **moddable** `getLastUsedProfileSlot(): int`
- **moddable** `getProfileDir(slot: int): string`
- **moddable** `getRootDataPath(): string`
- **moddable** `getSettingsPath(): string` (wrap only: scripts cannot call it)
- **moddable** `getStatsPath(): string`
- `jsonToRunStatistics(j: JsonNode): RunStatistics`
- **moddable** `jsonToSettings(jsonNode: JsonNode, settings: Settings)` (wrap only: scripts cannot call it)
- **moddable** `loadLastRunStats(): RunStatistics`
- **moddable** `loadProfileDifficulty(slot: int): GameDifficulty`
- **moddable** `loadSettings(settings: Settings): bool`
- **moddable** `markStorySeen(settings: Settings, cine: StoryCinematic)`
- **moddable** `migrateLegacySaveFiles()`
- `needObject(j: JsonNode)`
- **moddable** `profileExists(slot: int): bool`
- **moddable** `runStatisticsToJson(runStats: RunStatistics): JsonNode`
- **moddable** `saveLastRunStats(runStats: RunStatistics): bool`
- **moddable** `saveSettings(settings: Settings): bool`
- **moddable** `setLastUsedProfileSlot(slot: int)`
- **moddable** `settingsToJson(settings: Settings): JsonNode` (wrap only: scripts cannot call it)
- **moddable** `snapUIScale(scale: float32): float32` (wrap only: scripts cannot call it)
- **moddable** `storyOutdated(settings: Settings, cine: StoryCinematic): bool`
- **moddable** `storyPending(settings: Settings, cine: StoryCinematic): bool`
- **moddable** `uiScalePresetIndex(scale: float32): int`

### `settings`

- **moddable** `applySettings(settings: Settings)`
- **moddable** `damageNumberScaleOf(settings: Settings): float32`
- **moddable** `initSettings(): Settings`
- **moddable** `isPowerUpDiscovered(pt: PowerUpType): bool`
- **moddable** `newDefaultSettings(): Settings`
- **moddable** `reloadSettingsFromDisk(settings: Settings)`
- **moddable** `screenShakeScaleOf(settings: Settings): float32`
- **moddable** `showDamageNumbersOf(settings: Settings): bool`
- **moddable** `uiScaleOf(settings: Settings): float32`

### `settings_window`

- **moddable** `controlsLayout(contentY: int, contentH: int): ControlsLayout` (wrap only: scripts cannot call it)
- **moddable** `drawAudioTab(settingsWin: SettingsWindow, contentX: int, contentY: int, contentW: int, contentH: int)` (wrap only: scripts cannot call it)
- **moddable** `drawCheckbox(x: int, y: int, size: int, checked: bool, hovered: bool)`
- **moddable** `drawCinematicsTab(settingsWin: SettingsWindow, contentX: int, contentY: int, contentW: int, contentH: int)` (wrap only: scripts cannot call it)
- **moddable** `drawControlsTab(settingsWin: SettingsWindow, contentX: int, contentY: int, contentW: int, contentH: int)`
- **moddable** `drawGameplayTab(settingsWin: SettingsWindow, contentX: int, contentY: int, contentW: int, contentH: int)` (wrap only: scripts cannot call it)
- **moddable** `drawGraphicsTab(settingsWin: SettingsWindow, contentX: int, contentY: int, contentW: int, contentH: int)` (wrap only: scripts cannot call it)
- **moddable** `drawInterfaceTab(settingsWin: SettingsWindow, contentX: int, contentY: int, contentW: int, contentH: int)` (wrap only: scripts cannot call it)
- **moddable** `drawSectionHeader(x: int, y: int, width: int, title: string, iconChar: char, color: Color)` (wrap only: scripts cannot call it)
- **moddable** `drawSettingsWindow(settingsWin: SettingsWindow)`
- **moddable** `drawSlider(x: int, y: int, width: int, height: int, value: float32, hovered: bool, showTicks: bool, tickValues: seq[int])` (wrap only: scripts cannot call it)
- **moddable** `drawTab(tabName: string, x: int, y: int, width: int, height: int, isActive: bool, isHovered: bool)` (wrap only: scripts cannot call it)
- **moddable** `newSettingsWindow(screenWidth: int, screenHeight: int, settings: Settings, stats: Statistics, advancementProfile: AdvancementProfile, rogueliteProfile: RogueliteProfile): SettingsWindow`
- **moddable** `tabContentOriginY(window: OSWindow): int` (wrap only: scripts cannot call it)
- **moddable** `updateSettingsWindow(settingsWin: SettingsWindow, dt: float32, screenWidth: int, screenHeight: int, allWindows: openArray[OSWindow]): tuple[shouldClose: bool, fullscreenToggle: bool]`
- **moddable** `wantsTextInput(settingsWin: SettingsWindow): bool`

### `shapes`

- `drawCheaterHat(pos: Vector2, radius: float32, time: float32, alpha: float32)`
- `drawMiniCube(center: Vector2, size: float32, time: float32, skin: CubeSkinType)`
- `drawPlayerShape(pos: Vector2, radius: float32, shapeType: ShapeType, baseColor: Color, secondaryColor: Color, coreColor: Color, time: float32, rotation: float32, pulse: float32, glowIntensity: float32)`
- `drawRogueliteClassCosmetic(pos: Vector2, radius: float32, time: float32, kit: int, bodyColor: Color)`
- `drawTopHat(pos: Vector2, radius: float32, time: float32, alpha: float32, accent: Color)`
- `getShapeData(shapeType: ShapeType): ShapeData`
- `initializeShapes()`

### `shooting`

- **moddable** `fireDoubleShotBurst(game: Game, direction: Vector2, hasMultiShot: bool)`
- **moddable** `shootBullet(game: Game, direction: Vector2)`

### `shop_window`

- **moddable** `drawBulletShapePreview(x: int, y: int, shapeType: BulletShapeType, time: float32, isSelected: bool, isHovered: bool, isUnlocked: bool, canBuy: bool, cost: CosmeticCost, costText: string)` (wrap only: scripts cannot call it)
- **moddable** `drawBulletSkinPreview(x: int, y: int, skinType: BulletSkinType, time: float32, isSelected: bool, isHovered: bool, isUnlocked: bool, canBuy: bool, cost: CosmeticCost, costText: string)` (wrap only: scripts cannot call it)
- **moddable** `drawCubeSkinPreview(x: int, y: int, skinType: CubeSkinType, time: float32, isSelected: bool, isHovered: bool, isUnlocked: bool, canBuy: bool, cost: CosmeticCost, costText: string)` (wrap only: scripts cannot call it)
- **moddable** `drawDesktopBgPreview(x: int, y: int, bgType: DesktopBgType, time: float32, isSelected: bool, isHovered: bool, isUnlocked: bool, canBuy: bool, cost: CosmeticCost, costText: string)` (wrap only: scripts cannot call it)
- **moddable** `drawParticlePreview(x: int, y: int, particleType: ParticleSkinType, time: float32, isSelected: bool, isHovered: bool, isUnlocked: bool, canBuy: bool, cost: CosmeticCost, costText: string)` (wrap only: scripts cannot call it)
- **moddable** `drawPlayerSkinPreview(x: int, y: int, skinType: SkinType, shapeType: ShapeType, time: float32, isSelected: bool, isHovered: bool, isUnlocked: bool, canBuy: bool, cost: CosmeticCost, costText: string)` (wrap only: scripts cannot call it)
- **moddable** `drawShapePreview(x: int, y: int, shapeType: ShapeType, time: float32, isSelected: bool, isHovered: bool, isUnlocked: bool, canBuy: bool, cost: CosmeticCost, costText: string)` (wrap only: scripts cannot call it)
- **moddable** `drawShopWindow(shop: ShopWindow)`
- **moddable** `newShopWindow(screenWidth: int, screenHeight: int, currentPlayerSkin: SkinType, currentBulletSkin: BulletSkinType, currentShape: ShapeType, currentParticle: ParticleSkinType, currentBulletShape: BulletShapeType, rogueliteProfile: RogueliteProfile): ShopWindow`
- **moddable** `saveSkinSelectionImmediately(shop: ShopWindow)` (wrap only: scripts cannot call it)
- **moddable** `updateShopWindow(shop: ShopWindow, dt: float32, screenWidth: int, screenHeight: int, allWindows: openArray[OSWindow]): bool`
- **moddable** `visibleCosmeticIndices(kind: CosmeticKind, query: string): seq[int]` (wrap only: scripts cannot call it)
- **moddable** `wantsTextInput(shop: ShopWindow): bool`
- **moddable** `wrapDescAutoSize(text: string, maxWidth: int32, startSize: int32, minSize: int32): tuple[line1: string, line2: string, line3: string, fontSize: int32]` (wrap only: scripts cannot call it)
- **moddable** `wrapTwoLines(text: string, maxWidth: int32, fontSize: int32): tuple[line1: string, line2: string]` (wrap only: scripts cannot call it)

### `skins`

- **moddable** `getSkinColors(skinType: SkinType, time: float32): tuple[primary: Color, secondary: Color, core: Color]`
- **moddable** `getSkinData(skinType: SkinType): SkinData`
- **moddable** `initializeSkins()`

### `sound`

- `assetGenBusy(): bool`
- `assetGenCompleted(): int`
- **moddable** `assetGenLabel(): string`
- `assetGenOnMusic(): bool`
- **moddable** `assetGenProgress(): float32`
- **moddable** `closeSoundSystem(sys: SoundSystem)`
- **moddable** `finishAssetGeneration()`
- **moddable** `holdGameMusic(held: bool)`
- **moddable** `initSoundSystem(): SoundSystem`
- **moddable** `isScoreTrack(track: MusicTrack): bool`
- **moddable** `loadSoundsStep(sys: SoundSystem, budget: int): bool`
- **moddable** `playMusic(track: MusicTrack, tier: int)`
- **moddable** `playSound(soundType: SoundType, volumeMultiplier: float32, pitch: float32)`
- **moddable** `restoreVanillaSounds()`
- **moddable** `scoreLength(shots: openArray[float32]): float32` (wrap only: scripts cannot call it)
- **moddable** `scoreTime(shots: openArray[float32], index: int, local: float32): float32` (wrap only: scripts cannot call it)
- **moddable** `setGameVolume(volume: float32)`
- **moddable** `setModMusic(track: MusicTrack, path: string): bool`
- **moddable** `setModSound(st: SoundType, path: string): bool`
- **moddable** `setMusicMuffled(muffled: bool)`
- **moddable** `setMusicVolume(volume: float32)`
- **moddable** `shotStart(shots: openArray[float32], index: int): float32` (wrap only: scripts cannot call it)
- **moddable** `soundLoadLabel(): string`
- **moddable** `soundLoadProgress(): float32`
- **moddable** `startAssetGeneration(): int`
- **moddable** `startScore(track: MusicTrack): bool`
- **moddable** `stopMusic()`
- **moddable** `syncScore(track: MusicTrack, position: float32, rate: float32)`
- **moddable** `totalLength(shots: openArray[float32]): float32` (wrap only: scripts cannot call it)
- **moddable** `updateMusic()`

### `statistics`

- **moddable** `formatTime(seconds: float32): string`
- **moddable** `hasDefeatedBoss(stats: Statistics, bossDefinitionID: int): bool`
- **moddable** `initStatistics(): Statistics`
- **moddable** `jsonToStatistics(jsonNode: JsonNode, stats: Statistics)` (wrap only: scripts cannot call it)
- **moddable** `loadStatistics(stats: Statistics): bool`
- **moddable** `markBossDefeated(stats: Statistics, bossDefinitionID: int)`
- **moddable** `resetStatistics(stats: Statistics)`
- **moddable** `saveStatistics(stats: Statistics): bool`
- **moddable** `statisticsToJson(stats: Statistics): JsonNode` (wrap only: scripts cannot call it)
- **moddable** `updateStatsForMode(stats: Statistics, mode: GameMode, scoreReached: int, timeSurvived: float32, kills: int, coins: int, bossesKilled: int, died: bool, newGame: bool, runKills: int, runCoins: int, runTime: float32)`

### `stats_window`

- **moddable** `buildDamageRanking(runStats: RunStatistics): seq[(PowerUpType, float32)]` (wrap only: scripts cannot call it)
- **moddable** `buildHealingSources(runStats: RunStatistics): seq[HealingSourceRow]` (wrap only: scripts cannot call it)
- **moddable** `drawListScrollbar(x: int, y: int, height: int, scrollOffset: int, contentHeight: int, viewportHeight: int)` (wrap only: scripts cannot call it)
- **moddable** `drawMetricCard(x: int, y: int, width: int, height: int, title: string, value: string, icon: char, color: Color)` (wrap only: scripts cannot call it)
- **moddable** `drawMiniGraph(x: int, y: int, width: int, height: int, title: string, dataPoints: seq[(float32, float32)], maxValue: float32, color: Color, animTime: float32)` (wrap only: scripts cannot call it)
- **moddable** `drawStatLine(x: int, y: int, label: string, value: string, valueColor: Color)` (wrap only: scripts cannot call it)
- **moddable** `drawStatPanel(x: int, y: int, width: int, height: int, title: string)` (wrap only: scripts cannot call it)
- **moddable** `drawStatsWindow(statsWin: StatsWindow, game: Game)`
- **moddable** `formatDuration(seconds: float32): string` (wrap only: scripts cannot call it)
- **moddable** `formatLargeNumber(value: float32): string` (wrap only: scripts cannot call it)
- **moddable** `formatPercent(value: float32): string` (wrap only: scripts cannot call it)
- **moddable** `getQualityColor(value: float32, threshold: float32): Color` (wrap only: scripts cannot call it)
- **moddable** `newStatsWindow(screenWidth: int, screenHeight: int, stats: Statistics): StatsWindow`
- **moddable** `powerUpListGeometry(window: OSWindow): array[0 .. 2, PowerUpListGeom]` (wrap only: scripts cannot call it)
- **moddable** `powerUpRowCounts(runStats: RunStatistics): array[0 .. 2, int]` (wrap only: scripts cannot call it)
- **moddable** `rankingColumns(g: PowerUpListGeom): tuple[rankX: int, nameX: int, nameMax: int, valueRight: int, percentRight: int,
      scrollbarX: int]` (wrap only: scripts cannot call it)
- **moddable** `timelineColumns(g: PowerUpListGeom): tuple[timeX: int, nameX: int, nameMax: int, levelRight: int, scrollbarX: int]` (wrap only: scripts cannot call it)
- **moddable** `updateStatsWindow(statsWin: StatsWindow, dt: float32, screenWidth: int, screenHeight: int, allWindows: openArray[OSWindow]): bool`

### `survival`

- **moddable** `addSurvivalEnemy(game: Game, pos: Vector2, enemyType: EnemyType, tag: SurvivalTag, hpMult: float32, speedMult: float32, allowElite: bool): Enemy` (wrap only: scripts cannot call it)
- **moddable** `canOpenSurvivalCache(game: Game): bool` (wrap only: scripts cannot call it)
- **moddable** `cancelSurvivalEvent(game: Game)` (wrap only: scripts cannot call it)
- **moddable** `drawSurvivalBannerGutter(game: Game, gutterX: int32, gutterW: int32, topY: int32): int32`
- **moddable** `drawSurvivalBanner(game: Game, screenWidth: int32, topY: int32)`
- **moddable** `drawSurvivalCacheReveal(game: Game, screenWidth: int32, screenHeight: int32)`
- **moddable** `drawSurvivalChests(game: Game)` (wrap only: scripts cannot call it)
- **moddable** `drawSurvivalDockCard(game: Game, x: int32, y: int32, withLevel: bool): int32`
- **moddable** `drawSurvivalEventsOver(game: Game)` (wrap only: scripts cannot call it)
- **moddable** `drawSurvivalEventsUnder(game: Game)` (wrap only: scripts cannot call it)
- **moddable** `drawSurvivalHUD(game: Game, screenWidth: int32, screenHeight: int32)`
- **moddable** `drawSurvivalSpawnMarkers(game: Game)` (wrap only: scripts cannot call it)
- **moddable** `drawSurvivalWorldOver(game: Game)`
- **moddable** `drawSurvivalWorldUnder(game: Game)`
- **moddable** `dropSurvivalCache(game: var Game, pos: Vector2, tier: SurvivalCacheTier)` (wrap only: scripts cannot call it)
- **moddable** `formatSurvivalClock(seconds: float32): string`
- **moddable** `newSurvivalEnemy(game: Game, pos: Vector2, enemyType: EnemyType, tag: SurvivalTag, hpMult: float32, speedMult: float32, allowElite: bool): Enemy`
- **moddable** `onSurvivalBossDefeated(game: var Game, bossPos: Vector2): bool`
- **moddable** `onSurvivalEnemyKilled(game: var Game, enemy: Enemy)`
- **moddable** `onSurvivalEventKill(game: var Game, enemy: Enemy)` (wrap only: scripts cannot call it)
- **moddable** `openSurvivalCache(game: var Game, tier: SurvivalCacheTier, at: Vector2): bool` (wrap only: scripts cannot call it)
- **moddable** `pickFodderType(game: Game): EnemyType` (wrap only: scripts cannot call it)
- **moddable** `prepareSurvivalBossArrival(game: var Game)`
- **moddable** `queueRing(game: Game, count: int, radius: float32, delay: float32, tag: SurvivalTag, allowElite: bool): int` (wrap only: scripts cannot call it)
- **moddable** `queueSurvivalSpawn(game: Game, pos: Vector2, enemyType: EnemyType, delay: float32, tag: SurvivalTag, hpMult: float32, speedMult: float32, allowElite: bool, telegraph: bool): bool` (wrap only: scripts cannot call it)
- **moddable** `reclaimSurvivalFodder(game: Game, keep: int)` (wrap only: scripts cannot call it)
- **moddable** `setSurvivalBanner(game: Game, kind: SurvivalBannerKind, event: SurvivalEventKind, modKey: string)` (wrap only: scripts cannot call it)
- **moddable** `startSurvivalEvent(game: var Game, kind: SurvivalEventKind, modKey: string)`
- **moddable** `survivalAliveCount(game: Game): int`
- **moddable** `survivalCacheAccent(tier: SurvivalCacheTier): Color`
- **moddable** `survivalCacheFallbackShards(tier: SurvivalCacheTier): int` (wrap only: scripts cannot call it)
- **moddable** `survivalCacheLevels(tier: SurvivalCacheTier): int` (wrap only: scripts cannot call it)
- **moddable** `survivalCacheNameKey(tier: SurvivalCacheTier): TranslationKey` (wrap only: scripts cannot call it)
- **moddable** `survivalCacheWalls(tier: SurvivalCacheTier): int`
- **moddable** `survivalDensityTarget(game: Game): float32` (wrap only: scripts cannot call it)
- **moddable** `survivalEventActive(game: Game): bool` (wrap only: scripts cannot call it)
- **moddable** `survivalEventColor(kind: SurvivalEventKind): Color` (wrap only: scripts cannot call it)
- **moddable** `survivalEventColor(kind: SurvivalEventKind, modKey: string): Color` (wrap only: scripts cannot call it)
- **moddable** `survivalEventDuration(kind: SurvivalEventKind): float32` (wrap only: scripts cannot call it)
- **moddable** `survivalEventHintKey(kind: SurvivalEventKind): TranslationKey` (wrap only: scripts cannot call it)
- **moddable** `survivalEventHint(kind: SurvivalEventKind, modKey: string): string` (wrap only: scripts cannot call it)
- **moddable** `survivalEventNameKey(kind: SurvivalEventKind): TranslationKey` (wrap only: scripts cannot call it)
- **moddable** `survivalEventName(kind: SurvivalEventKind, modKey: string): string`
- **moddable** `survivalHudStackBottom(game: Game): int32`
- **moddable** `survivalPhaseDescKey(phase: SurvivalPhase): TranslationKey` (wrap only: scripts cannot call it)
- **moddable** `survivalPhaseNameKey(phase: SurvivalPhase): TranslationKey`
- **moddable** `survivalPhaseReachedLabel(game: Game): string`
- **moddable** `survivalRefillRate(game: Game): float32` (wrap only: scripts cannot call it)
- **moddable** `survivalTrackerInfo(game: Game): tuple[detail: string, frac: float32, remaining: float32]` (wrap only: scripts cannot call it)
- **moddable** `updateSurvivalCacheReveal(game: Game, dt: float32): bool`
- **moddable** `updateSurvivalChests(game: var Game, dt: float32)` (wrap only: scripts cannot call it)
- **moddable** `updateSurvivalDensity(game: Game, dt: float32)` (wrap only: scripts cannot call it)
- **moddable** `updateSurvivalEvent(game: var Game, dt: float32)`
- **moddable** `updateSurvivalFormations(game: Game)` (wrap only: scripts cannot call it)
- **moddable** `updateSurvivalPending(game: Game, dt: float32)` (wrap only: scripts cannot call it)
- **moddable** `updateSurvivalScheduler(game: var Game)` (wrap only: scripts cannot call it)
- **moddable** `updateSurvival(game: var Game, dt: float32)`

### `survival_end_cinematic`

- **moddable** `drawSurvivalEndCinematic(c: SurvivalEndCinematic, screenWidth: int, screenHeight: int)`
- `newSurvivalEndCinematic(): SurvivalEndCinematic`
- **moddable** `newSurvivalEndCutscene(): Cutscene` (wrap only: scripts cannot call it)
- **moddable** `updateSurvivalEndCinematic(c: SurvivalEndCinematic, dt: float32)`

### `suspend`

- **moddable** `deleteSuspendSnapshot(mode: GameMode, modMode: string)`
- `fromFlatty(s: string, i: var int, x: var DiscordClient)`
- `fromFlatty(s: string, i: var int, x: var DopamineState)`
- `fromFlatty(s: string, i: var int, x: var OSBackgroundState)`
- `fromFlatty(s: string, i: var int, x: var ParticlePool)`
- `fromFlatty(s: string, i: var int, x: var RogueliteProfile)`
- **moddable** `fromFlatty(s: string, i: var int, x: var array[puMod000 .. puMod255, float32])`
- `fromFlatty(s: string, i: var int, x: var array[puMod000 .. puMod255, float32])`
- `fromFlatty(s: string, i: var int, x: var pointer)` (parameter x is a pointer)
- **moddable** `getSuspendPath(mode: GameMode, modMode: string): string` (wrap only: scripts cannot call it)
- **moddable** `hasSuspendSnapshot(mode: GameMode, modMode: string): bool`
- `relinkSharedRefs(g: Game)`
- **moddable** `restoreGame(target: var Game): bool`
- **moddable** `suspendGame(game: Game)`
- `toFlatty(s: var string, x: DiscordClient)`
- `toFlatty(s: var string, x: DopamineState)`
- `toFlatty(s: var string, x: OSBackgroundState)`
- `toFlatty(s: var string, x: ParticlePool)`
- `toFlatty(s: var string, x: RogueliteProfile)`
- **moddable** `toFlatty(s: var string, x: array[puMod000 .. puMod255, float32])`
- `toFlatty(s: var string, x: array[puMod000 .. puMod255, float32])`
- `toFlatty(s: var string, x: pointer)` (parameter x is a pointer)

### `text_field`

- **moddable** `drawTextField(f: TextField, box: Rectangle, active: bool)`
- **moddable** `fieldStyle(fontSize: int32, ink: Color, accent: Color, padX: int32, align: TextAlign): TextFieldStyle`
- **moddable** `focusField(f: TextField, fields: openArray[TextField])`
- **moddable** `focusNext(fields: openArray[TextField], backwards: bool)`
- **moddable** `hasSelection(f: TextField): bool`
- **moddable** `insertText(f: TextField, s: string)`
- **moddable** `newTextField(style: TextFieldStyle, text: string, maxChars: int, allowed: set[char], multiline: bool, keepHistory: bool): TextField`
- **moddable** `selectAll(f: TextField)`
- **moddable** `selectedText(f: TextField): string`
- **moddable** `setText(f: TextField, s: string)`
- **moddable** `submitLine(f: TextField): string`
- **moddable** `typingIn(window: OSWindow, f: TextField): bool`
- **moddable** `updateTextFields(fields: openArray[TextField], boxes: openArray[Rectangle], dt: float32, active: bool): TextFieldInput`
- **moddable** `updateTextField(f: TextField, box: Rectangle, dt: float32, active: bool): TextFieldInput`

### `things`

- **moddable** `alive(t: ModThing): bool`
- **moddable** `collideThingBullets(game: Game)`
- **moddable** `damageThing(game: Game, t: ModThing, amount: float32, source: string): float32`
- **moddable** `drawThings(game: Game, layer: ThingLayer)`
- **moddable** `hazardHits(t: ModThing, p: Vector2, r: float32): bool` (wrap only: scripts cannot call it)
- **moddable** `joinThing(game: Game, t: ModThing, callback: ScriptValue, owner: int): bool`
- **moddable** `killThing(game: Game, t: ModThing)`
- **moddable** `overlapsCircle(t: ModThing, p: Vector2, r: float32): bool`
- **moddable** `removeThing(t: ModThing)`
- **moddable** `sweepThings(game: Game)`
- **moddable** `updateThings(game: Game, simDt: float32, effectiveDt: float32, grid: SpatialGrid, maxEnemyR: float32)`

### `tutorial`

- **moddable** `endTutorialSession()`
- **moddable** `isRead(step: TutorialStep): bool`
- **moddable** `isTutorialActive(game: Game): bool`
- **moddable** `isTutorialPractice(game: Game): bool`
- **moddable** `startTutorial(game: Game, practice: bool)`
- **moddable** `tutorialHoldsWaves(game: Game): bool`
- **moddable** `tutorialState(): TutorialState`
- **moddable** `tutorialSuppressesSaves(game: Game): bool`
- **moddable** `updateTutorial(game: Game, dt: float32): TutorialEvent`

### `tutorial_overlay`

- **moddable** `drawTutorialOverlay(game: Game, hudScale: float32)`

### `types`

- `addBulletSpeedDiminished(currentSpeed: float32, gain: float32): float32`
- `applyFireRateDiminished(currentRate: float32, scalingFactor: float32, exponent: float32, hardCap: float32): float32`
- `applyFrostChill(enemy: Enemy, amount: float32)`
- `applySlow(enemy: Enemy, amount: float32, duration: float32)`
- `calculateWaveEnemyCount(waveNumber: int): int`
- `canonicalBossId(id: int): int`
- `clockSweepHandAngle(warning: AttackWarning, hand: int, lifetimeOffset: float32): float32`
- `coopScale(perExtraPlayer: float32): float32`
- `defaultPvPConfig(): PvPConfig`
- `densityRebate(game: Game): float32`
- `densityWave(game: Game): int`
- `difficultyAllowsContinue(mode: GameMode, modMode: string): bool`
- **moddable** `difficultyBossCooldownMult(): float32`
- **moddable** `difficultyEliteChanceMult(): float32`
- **moddable** `difficultyEnemyDamageMult(): float32`
- **moddable** `difficultyEnemyHpMult(): float32`
- **moddable** `difficultyEnemySpeedMult(): float32`
- `difficultyMaxLives(mode: GameMode, modMode: string): int`
- **moddable** `difficultySpawnPaceMult(): float32`
- `effectiveSlow(enemy: Enemy): float32`
- `elementColor(elementType: ElementType): Color`
- `elementDamageType(elementType: ElementType): DamageType`
- `freezeRunTime(game: Game)`
- `getEffectiveSpeed(baseSpeed: float32, waveNumber: int): float32`
- **moddable** `inPickupRange(pos: Vector2, radius: float32, player: Player): bool`
- `initSurvivalState(): SurvivalState`
- `isOmegaBoss(id: int): bool`
- `isWaveBossId(id: int): bool`
- `livesRemaining(used: int, mode: GameMode, modMode: string): int`
- `modRestoreRule(modMode: string): ModRestoreRule`
- `multiplyBulletSpeedDiminished(currentSpeed: float32, multiplier: float32): float32`
- `newAttackWarning(x: float32, y: float32, attackType: AttackWarningType, duration: float32, sourceEnemyId: int): AttackWarning`
- `newBossLaserWarning(x: float32, y: float32, duration: float32, angles: seq[float32], length: float32, damage: int, laserDuration: float32, pattern: string, enemyType: EnemyType, sourceEnemyId: int): AttackWarning`
- `newLaser(x: float32, y: float32, direction: int, length: float32, thickness: float32, damage: int, duration: float32, rotation: float32, enemyType: EnemyType, sourceEnemyId: int): Laser`
- `newMeteorite(targetX: float32, targetY: float32, spawnX: float32, spawnY: float32, damage: int, warningTime: float32, sourceEnemyId: int): Meteorite`
- `newSatelliteLaserWarning(satelliteX: float32, satelliteY: float32, targetX: float32, targetY: float32, duration: float32, sourceEnemyId: int): AttackWarning`
- `orbitalSweepCenter(warning: AttackWarning): Vector2`
- `polylineLength(path: seq[Vector2]): float32`
- `restorePointsOffline(game: Game): bool`
- `restorePointsShown(game: Game): bool`
- `resumeRunTime(game: Game)`
- `ricochetSweptPath(path: seq[Vector2], frontDist: float32): seq[Vector2]`
- `runElapsedTime(game: Game): float32`
- `survivalBossBlockWave(bossNumber: int): int`
- `survivalBossId(bossNumber: int): int`
- `survivalBossTime(bossNumber: int): float32`
- `survivalNextBossTime(game: Game): float32`
- `survivalOvertimeMinutes(game: Game): float32`
- `survivalPhaseIndex(game: Game): int`
- `survivalPhaseProgress(game: Game): float32`
- `survivalPhase(game: Game): SurvivalPhase`
- `survivalRogueTime(index: int): float32`
- `teamFromInt(value: int): PvPTeam`
- `wallContactNormal(wall: Wall, p: Vector2): Vector2`
- `wallOverlapsCircle(wall: Wall, center: Vector2, radius: float32): bool`
- `waveDensityRebate(waveNumber: int): float32`

### `ui_helpers`

- **moddable** `bestFitFontSize(text: string, maxWidth: int32, preferredSize: int32, minSize: int32): int32`
- **moddable** `bestWrapFontSize(text: string, maxWidth: int32, preferredSize: int32, maxLines: int, minSize: int32): int32`
- **moddable** `drawCenteredTextFit(text: string, x: int32, y: int32, maxWidth: int32, fontSize: int32, color: Color, minSize: int32): int32`
- **moddable** `drawEndlessRestorePanel(x: int32, y: int32, width: int32, mode: GameMode, time: float32, height: int32)`
- **moddable** `drawLifeLostOverlay(screenW: int32, screenH: int32, used: int, maxLives: int, unlimitedSentinel: int, progress: float32)`
- **moddable** `drawLivesPanel(x: int32, y: int32, width: int32, used: int, maxLives: int, unlimitedSentinel: int, time: float32, height: int32)`
- **moddable** `drawRestorePointIcon(cx: float32, cy: float32, size: float32, body: Color, accent: Color, led: Color, spin: float32)` (wrap only: scripts cannot call it)
- **moddable** `drawTextFit(text: string, x: int32, y: int32, maxWidth: int32, fontSize: int32, color: Color, minSize: int32, align: TextAlign): int32`
- **moddable** `drawWrappedText(text: string, x: int, y: int, maxWidth: int, fontSize: int32, stockColor: Color, maxLines: int, lineGap: int, minSize: int32): int`
- **moddable** `fitPathTail(path: string, maxWidth: int32, fontSize: int32, sep: char): string`
- **moddable** `fitTextAndSize(text: string, maxWidth: int32, preferredSize: int32, minSize: int32): tuple[text: string, size: int32]`
- **moddable** `fitWithEllipsis(text: string, maxWidth: int32, fontSize: int32): string`
- **moddable** `wrapTextLines(text: string, maxWidth: int32, fontSize: int32, breakLongWords: bool): seq[string]`

### `ui_theme`

- **moddable** `activeTheme(): UiTheme`
- **moddable** `addTheme(th: UiTheme): bool`
- **moddable** `beginKeepAlpha()`
- **moddable** `beginThemeLayer(): bool`
- **moddable** `chooseTheme(id: string): bool`
- **moddable** `chosenTheme(): UiTheme`
- **moddable** `cornerRoundness(w: float32, h: float32, radius: float32): float32`
- **moddable** `drawCknLogo(cx: float32, cy: float32, size: float32, alpha: float32, arc: Color)`
- **moddable** `drawCknPanel(rect: Rectangle, radius: float32, fill: Color, border: Color, shadowAlpha: float32)`
- **moddable** `endKeepAlpha()`
- **moddable** `endThemeLayer(began: bool)`
- **moddable** `findTheme(id: string): UiTheme`
- **moddable** `newTheme(id: string, shell: ShellStyle, surface: Color, raised: Color, text: Color, muted: Color, accent: Color, owner: int, name: string, nameEs: string, wallpaper: int): UiTheme`
- `stockTheme(): UiTheme`
- **moddable** `themeIsLight(): bool`
- **moddable** `themeName(th: UiTheme): string`
- **moddable** `themeUnlocked(th: UiTheme): bool`
- `uiGlow(c: Color): Color`
- `uiGlow(r: int, g: int, b: int, a: int): Color`
- `uiInk(c: Color): Color`
- `uiInk(r: int, g: int, b: int, a: int): Color`
- `uiLine(c: Color): Color`
- `uiLine(r: int, g: int, b: int, a: int): Color`
- `uiOverlay(c: Color): Color`
- `uiOverlay(r: int, g: int, b: int, a: int): Color`
- `uiSurface(c: Color): Color`
- `uiSurface(r: int, g: int, b: int, a: int): Color`
- **moddable** `unforceTheme()` (wrap only: scripts cannot call it)
- **moddable** `unlockedThemes(): seq[UiTheme]`

### `utils`

- `brighten(color: Color, amount: float32): Color`
- `brighten(color: Color, amount: int, alpha: int): Color`
- `clamp01(v: float32): float32`
- `clampByteF(value: float32): uint8`
- `clampByte(value: int): uint8`
- `clearOf(c: Color): Color`
- `darken(color: Color, amount: int, alpha: int): Color`
- `easeOutCubic(t: float32): float32`
- `formatHealthDisplay(value: float32): string`
- `fract01(v: float32): float32`
- `hash01(seed: float32): float32`
- `lerpRgb(c: Color, target: Color, t: float32): Color`
- `rgba(r: int, g: int, b: int, a: float32): Color`
- `rgba(r: int, g: int, b: int, a: int): Color`
- `scaleAlpha(c: Color, k: float32): Color`
- `smoothstep(e0: float32, e1: float32, x: float32): float32`
- `smoothstep(t: float32): float32`
- `versionAtLeast(have: string, want: string): bool`
- `withAlpha(color: Color, alpha: float32): Color`
- `withAlpha(color: Color, alpha: int): Color`
- `withAlpha(color: Color, alpha: uint8): Color`
- `wrapCoord(value: float32, limit: float32): float32`

### `vec`

- `vec2(x: float32, y: float32): Vector2`
- `vec3(x: float32, y: float32, z: float32): Vector3`

### `wall`

- **moddable** `checkPlayerWallCollision(playerPos: Vector2, playerRadius: float32, wall: Wall): bool`
- **moddable** `drawWall(wall: Wall, player: Player)`
- **moddable** `isValidWallPlacement(pos: Vector2, playerPos: Vector2, walls: seq[Wall], enemies: seq[Enemy], radius: float32, worldWidth: int32, worldHeight: int32): bool`
- **moddable** `newWall(x: float32, y: float32, player: Player): Wall`
- **moddable** `processPendingWallRespawns(pending: var seq[PendingWallRespawn], walls: var seq[Wall], enemies: seq[Enemy], players: seq[Player], particlePool: ParticlePool, dt: float32)`
- **moddable** `processWallTurret(wall: var Wall, enemies: seq[Enemy], bullets: var seq[Bullet], player: Player, particlePool: ParticlePool, dt: float32, screenWidth: int32, screenHeight: int32)`
- **moddable** `takeDamage(wall: Wall, damage: float32)`
- **moddable** `updateWall(wall: Wall, dt: float32): bool`

### `warnings`

- **moddable** `addBossAttackWarningInto(warnings: var seq[AttackWarning], player: Player, enemy: Enemy, attack: BossAttack)`
- **moddable** `computeRicochetPath(startPos: Vector2, startDir: Vector2, bounces: int, screenWidth: int32, screenHeight: int32): seq[Vector2]` (wrap only: scripts cannot call it)
- **moddable** `isJuggernautCharge(specialData: string): bool` (wrap only: scripts cannot call it)
- **moddable** `spawnArcLatticeInto(warnings: var seq[AttackWarning], particlePool: ParticlePool, screenWidth: int32, screenHeight: int32, enemy: Enemy, attack: BossAttack, phase: BossPhaseDefinition)`
- **moddable** `spawnChaosWeaveInto(warnings: var seq[AttackWarning], particlePool: ParticlePool, player: Player, screenWidth: int32, screenHeight: int32, enemy: Enemy, attack: BossAttack, phase: BossPhaseDefinition)`
- **moddable** `spawnClockSweepInto(warnings: var seq[AttackWarning], particlePool: ParticlePool, player: Player, screenWidth: int32, screenHeight: int32, enemy: Enemy, attack: BossAttack, phase: BossPhaseDefinition)`
- **moddable** `spawnOmegaQuadrantsInto(warnings: var seq[AttackWarning], particlePool: ParticlePool, player: Player, screenWidth: int32, screenHeight: int32, enemy: Enemy, attack: BossAttack, phase: BossPhaseDefinition, lesson: bool)`
- **moddable** `spawnOrbitalSweepInto(warnings: var seq[AttackWarning], particlePool: ParticlePool, player: Player, screenWidth: int32, screenHeight: int32, enemy: Enemy, attack: BossAttack, phase: BossPhaseDefinition)`
- **moddable** `spawnPrismRaysInto(warnings: var seq[AttackWarning], particlePool: ParticlePool, player: Player, screenWidth: int32, screenHeight: int32, enemy: Enemy, attack: BossAttack, phase: BossPhaseDefinition)`
- **moddable** `spawnRicochetLaserInto(warnings: var seq[AttackWarning], particlePool: ParticlePool, player: Player, screenWidth: int32, screenHeight: int32, enemy: Enemy, attack: BossAttack, phase: BossPhaseDefinition)`
- **moddable** `spawnSeismicFissureInto(warnings: var seq[AttackWarning], particlePool: ParticlePool, player: Player, screenWidth: int32, screenHeight: int32, enemy: Enemy, attack: BossAttack, phase: BossPhaseDefinition)`
- **moddable** `spawnThunderstrikeInto(warnings: var seq[AttackWarning], particlePool: ParticlePool, player: Player, screenWidth: int32, screenHeight: int32, enemy: Enemy, attack: BossAttack, phase: BossPhaseDefinition)`
- **moddable** `spawnVoidRiftsInto(warnings: var seq[AttackWarning], particlePool: ParticlePool, player: Player, screenWidth: int32, screenHeight: int32, enemy: Enemy, attack: BossAttack, phase: BossPhaseDefinition)`

### `window_manager`

- **moddable** `applyWindowScales(wm: WindowManager, uiScale: float32, screenWidth: int, screenHeight: int)` (wrap only: scripts cannot call it)
- **moddable** `closeAllWindows(wm: WindowManager)`
- **moddable** `closeWindow(wm: WindowManager, id: WindowID)`
- **moddable** `drawAllWindows(wm: WindowManager, game: Game, uiScale: float32, screenWidth: int, screenHeight: int)`
- **moddable** `getAllWindows(wm: WindowManager): seq[OSWindow]` (wrap only: scripts cannot call it)
- **moddable** `getVisibleWindows(wm: WindowManager): seq[OSWindow]` (wrap only: scripts cannot call it)
- **moddable** `handleWindowClick(wm: WindowManager, uiScale: float32, screenWidth: int, screenHeight: int): bool`
- **moddable** `isMouseOverAnyWindow(wm: WindowManager, uiScale: float32, screenWidth: int, screenHeight: int): bool`
- **moddable** `newWindowManager(screenWidth: int, screenHeight: int, gameSettings: Settings, gameStats: Statistics, advancementProfile: AdvancementProfile, rogueliteProfile: RogueliteProfile): WindowManager`
- **moddable** `openModApp(wm: WindowManager, key: string, uiScale: float32, screenWidth: int, screenHeight: int)`
- **moddable** `openWindow(wm: WindowManager, id: WindowID)`
- **moddable** `relayoutWindows(wm: WindowManager, uiScale: float32, screenWidth: int, screenHeight: int)`
- **moddable** `unfocusAllWindows(wm: WindowManager)`
- **moddable** `updateAllWindows(wm: WindowManager, dt: float32, uiScale: float32, screenWidth: int, screenHeight: int, currentGame: Game): WindowUpdateResult`
- **moddable** `wantsTextInput(wm: WindowManager): bool`
- **moddable** `windowUIScale(window: OSWindow, requested: float32, screenWidth: int, screenHeight: int): float32` (wrap only: scripts cannot call it)
- **moddable** `windowViewport(window: OSWindow, requested: float32, screenWidth: int, screenHeight: int): tuple[scale: float32, w: int, h: int]`

### `xp_orb`

- **moddable** `collectAllXpOrbs(game: Game)`
- **moddable** `collectPickup(game: Game, orb: XpOrb): bool`
- **moddable** `drawGameXpOrbs(game: Game)`
- **moddable** `drawXpOrb(orb: XpOrb)` (wrap only: scripts cannot call it)
- **moddable** `dropEnemyXp(game: Game, enemy: Enemy)`
- **moddable** `enemyXpValue(enemy: Enemy): int` (wrap only: scripts cannot call it)
- **moddable** `newXpOrb(x: float32, y: float32, value: int): XpOrb`
- **moddable** `pickupAlive(game: Game, orb: XpOrb, dt: float32, count: int): bool`
- **moddable** `pickupTrail(orb: XpOrb): Color`
- **moddable** `updateGameXpOrbs(game: Game, dt: float32)`
- **moddable** `xpRequiredForLevel(level: int, mode: GameMode): int`

## raylib

`rl.<function>` is raylib, `rl.gl.<function>` rlgl: vectors, rectangles and colours are tables, and textures, fonts, sounds... are handles (one a script loads unloads itself once dropped).

- `rl.beginBlendMode(mode: BlendMode)`
- `rl.beginMode2D(camera: Camera2D)`
- `rl.beginMode3D(camera: Camera3D)`
- `rl.beginScissorMode(x: int32, y: int32, width: int32, height: int32)`
- `rl.beginShaderMode(shader: Shader)`
- `rl.beginTextureMode(target: RenderTexture2D)`
- `rl.beginVrStereoMode(config: VrStereoConfig)`
- `rl.boneCount(x: Mesh): int32`
- `rl.boneCount(x: ModelAnimation): uint32`
- `rl.boneCount(x: ModelSkeleton): uint32`
- `rl.capacity(x: AutomationEventList): int` (parameter x is a AutomationEventList)
- `rl.checkCollisionBoxSphere(box: BoundingBox, center: Vector3, radius: float32): bool`
- `rl.checkCollisionBoxes(box1: BoundingBox, box2: BoundingBox): bool`
- `rl.checkCollisionCircleLine(center: Vector2, radius: float32, p1: Vector2, p2: Vector2): bool`
- `rl.checkCollisionCircleRec(center: Vector2, radius: float32, rec: Rectangle): bool`
- `rl.checkCollisionCircles(center1: Vector2, radius1: float32, center2: Vector2, radius2: float32): bool`
- `rl.checkCollisionLines(startPos1: Vector2, endPos1: Vector2, startPos2: Vector2, endPos2: Vector2, collisionPoint: var Vector2): bool`
- `rl.checkCollisionPointCircle(point: Vector2, center: Vector2, radius: float32): bool`
- `rl.checkCollisionPointLine(point: Vector2, p1: Vector2, p2: Vector2, threshold: int32): bool`
- `rl.checkCollisionPointPoly(point: Vector2, points: openArray[Vector2]): bool`
- `rl.checkCollisionPointRec(point: Vector2, rec: Rectangle): bool`
- `rl.checkCollisionPointTriangle(point: Vector2, p1: Vector2, p2: Vector2, p3: Vector2): bool`
- `rl.checkCollisionRecs(rec1: Rectangle, rec2: Rectangle): bool`
- `rl.checkCollisionSpheres(center1: Vector3, radius1: float32, center2: Vector3, radius2: float32): bool`
- `rl.clearBackground(color: Color)`
- `rl.clearWindowState(flags: Flags[ConfigFlags])`
- `rl.colorAlphaBlend(dst: Color, src: Color, tint: Color): Color`
- `rl.colorAlpha(color: Color, alpha: float32): Color`
- `rl.colorBrightness(color: Color, factor: float32): Color`
- `rl.colorContrast(color: Color, contrast: float32): Color`
- `rl.colorFromHSV(hue: float32, saturation: float32, value: float32): Color`
- `rl.colorFromNormalized(normalized: Vector4): Color`
- `rl.colorLerp(color1: Color, color2: Color, factor: float32): Color`
- `rl.colorNormalize(color: Color): Vector4`
- `rl.colorTint(color: Color, tint: Color): Color`
- `rl.colorToHSV(color: Color): Vector3`
- `rl.colorToInt(color: Color): int32`
- `rl.disableCursor()`
- `rl.disableEventWaiting()`
- `rl.drawBillboard(camera: Camera, texture: Texture2D, position: Vector3, scale: float32, tint: Color)`
- `rl.drawBillboard(camera: Camera, texture: Texture2D, rec: Rectangle, position: Vector3, size: Vector2, tint: Color)`
- `rl.drawBillboard(camera: Camera, texture: Texture2D, rec: Rectangle, position: Vector3, up: Vector3, size: Vector2, origin: Vector2, rotation: float32, tint: Color)`
- `rl.drawBoundingBox(box: BoundingBox, color: Color)`
- `rl.drawCapsuleWires(startPos: Vector3, endPos: Vector3, radius: float32, rings: int32, slices: int32, color: Color)`
- `rl.drawCapsule(startPos: Vector3, endPos: Vector3, radius: float32, rings: int32, slices: int32, color: Color)`
- `rl.drawCircle3D(center: Vector3, radius: float32, rotationAxis: Vector3, rotationAngle: float32, color: Color)`
- `rl.drawCircleGradient(center: Vector2, radius: float32, inner: Color, outer: Color)`
- `rl.drawCircleLines(center: Vector2, radius: float32, color: Color)`
- `rl.drawCircleLines(center: Vector2, radius: float32, thick: float32, color: Color)`
- `rl.drawCircleLines(centerX: int32, centerY: int32, radius: float32, color: Color)`
- `rl.drawCircleSectorLines(center: Vector2, radius: float32, startAngle: float32, endAngle: float32, segments: int32, color: Color)`
- `rl.drawCircleSectorLines(center: Vector2, radius: float32, startAngle: float32, endAngle: float32, segments: int32, thick: float32, color: Color)`
- `rl.drawCircleSector(center: Vector2, radius: float32, startAngle: float32, endAngle: float32, segments: int32, color: Color)`
- `rl.drawCircle(center: Vector2, radius: float32, color: Color)`
- `rl.drawCircle(centerX: int32, centerY: int32, radius: float32, color: Color)`
- `rl.drawCubeWires(position: Vector3, size: Vector3, color: Color)`
- `rl.drawCubeWires(position: Vector3, width: float32, height: float32, length: float32, color: Color)`
- `rl.drawCube(position: Vector3, size: Vector3, color: Color)`
- `rl.drawCube(position: Vector3, width: float32, height: float32, length: float32, color: Color)`
- `rl.drawCylinderWires(position: Vector3, radiusTop: float32, radiusBottom: float32, height: float32, sides: int32, color: Color)`
- `rl.drawCylinderWires(startPos: Vector3, endPos: Vector3, startRadius: float32, endRadius: float32, sides: int32, color: Color)`
- `rl.drawCylinder(position: Vector3, radiusTop: float32, radiusBottom: float32, height: float32, sides: int32, color: Color)`
- `rl.drawCylinder(startPos: Vector3, endPos: Vector3, startRadius: float32, endRadius: float32, sides: int32, color: Color)`
- `rl.drawEllipseLines(center: Vector2, radiusH: float32, radiusV: float32, color: Color)`
- `rl.drawEllipseLines(center: Vector2, radiusH: float32, radiusV: float32, thick: float32, color: Color)`
- `rl.drawEllipseLines(centerX: int32, centerY: int32, radiusH: float32, radiusV: float32, color: Color)`
- `rl.drawEllipse(center: Vector2, radiusH: float32, radiusV: float32, color: Color)`
- `rl.drawEllipse(centerX: int32, centerY: int32, radiusH: float32, radiusV: float32, color: Color)`
- `rl.drawFPS(posX: int32, posY: int32)`
- `rl.drawGrid(slices: int32, spacing: float32)`
- `rl.drawLine3D(startPos: Vector3, endPos: Vector3, color: Color)`
- `rl.drawLineBezier(startPos: Vector2, endPos: Vector2, thick: float32, color: Color)`
- `rl.drawLineDashed(startPos: Vector2, endPos: Vector2, dashSize: int32, spaceSize: int32, color: Color)`
- `rl.drawLineStrip(points: openArray[Vector2], color: Color)`
- `rl.drawLine(startPos: Vector2, endPos: Vector2, color: Color)`
- `rl.drawLine(startPos: Vector2, endPos: Vector2, thick: float32, color: Color)`
- `rl.drawLine(startPosX: int32, startPosY: int32, endPosX: int32, endPosY: int32, color: Color)`
- `rl.drawMeshInstanced(mesh: Mesh, material: Material, transforms: openArray[Matrix])`
- `rl.drawMesh(mesh: Mesh, material: Material, transform: Matrix)`
- `rl.drawModelWires(model: Model, position: Vector3, rotationAxis: Vector3, rotationAngle: float32, scale: Vector3, tint: Color)`
- `rl.drawModelWires(model: Model, position: Vector3, scale: float32, tint: Color)`
- `rl.drawModel(model: Model, position: Vector3, rotationAxis: Vector3, rotationAngle: float32, scale: Vector3, tint: Color)`
- `rl.drawModel(model: Model, position: Vector3, scale: float32, tint: Color)`
- `rl.drawPixel(posX: int32, posY: int32, color: Color)`
- `rl.drawPixel(position: Vector2, color: Color)`
- `rl.drawPlane(centerPos: Vector3, size: Vector2, color: Color)`
- `rl.drawPoint3D(position: Vector3, color: Color)`
- `rl.drawPolyLines(center: Vector2, sides: int32, radius: float32, rotation: float32, color: Color)`
- `rl.drawPolyLines(center: Vector2, sides: int32, radius: float32, rotation: float32, thick: float32, color: Color)`
- `rl.drawPoly(center: Vector2, sides: int32, radius: float32, rotation: float32, color: Color)`
- `rl.drawRay(ray: Ray, color: Color)`
- `rl.drawRectangleGradientH(posX: int32, posY: int32, width: int32, height: int32, left: Color, right: Color)`
- `rl.drawRectangleGradientV(posX: int32, posY: int32, width: int32, height: int32, top: Color, bottom: Color)`
- `rl.drawRectangleGradient(rec: Rectangle, col1: Color, col2: Color, col3: Color, col4: Color)`
- `rl.drawRectangleLines(posX: int32, posY: int32, width: int32, height: int32, color: Color)`
- `rl.drawRectangleLines(rec: Rectangle, thick: float32, color: Color)`
- `rl.drawRectangleRoundedLines(rec: Rectangle, roundness: float32, segments: int32, color: Color)`
- `rl.drawRectangleRoundedLines(rec: Rectangle, roundness: float32, segments: int32, thick: float32, color: Color)`
- `rl.drawRectangleRounded(rec: Rectangle, roundness: float32, segments: int32, color: Color)`
- `rl.drawRectangle(posX: int32, posY: int32, width: int32, height: int32, color: Color)`
- `rl.drawRectangle(position: Vector2, size: Vector2, color: Color)`
- `rl.drawRectangle(rec: Rectangle, color: Color)`
- `rl.drawRectangle(rec: Rectangle, origin: Vector2, rotation: float32, color: Color)`
- `rl.drawRingLines(center: Vector2, innerRadius: float32, outerRadius: float32, startAngle: float32, endAngle: float32, segments: int32, color: Color)`
- `rl.drawRingLines(center: Vector2, innerRadius: float32, outerRadius: float32, startAngle: float32, endAngle: float32, segments: int32, thick: float32, color: Color)`
- `rl.drawRing(center: Vector2, innerRadius: float32, outerRadius: float32, startAngle: float32, endAngle: float32, segments: int32, color: Color)`
- `rl.drawSphereWires(centerPos: Vector3, radius: float32, rings: int32, slices: int32, color: Color)`
- `rl.drawSphere(centerPos: Vector3, radius: float32, color: Color)`
- `rl.drawSphere(centerPos: Vector3, radius: float32, rings: int32, slices: int32, color: Color)`
- `rl.drawSplineBasis(points: openArray[Vector2], thick: float32, color: Color)`
- `rl.drawSplineBezierCubic(points: openArray[Vector2], thick: float32, color: Color)`
- `rl.drawSplineBezierQuadratic(points: openArray[Vector2], thick: float32, color: Color)`
- `rl.drawSplineCatmullRom(points: openArray[Vector2], thick: float32, color: Color)`
- `rl.drawSplineLinear(points: openArray[Vector2], thick: float32, color: Color)`
- `rl.drawSplineSegmentBasis(p1: Vector2, p2: Vector2, p3: Vector2, p4: Vector2, thick: float32, color: Color)`
- `rl.drawSplineSegmentBezierCubic(p1: Vector2, c2: Vector2, c3: Vector2, p4: Vector2, thick: float32, color: Color)`
- `rl.drawSplineSegmentBezierQuadratic(p1: Vector2, c2: Vector2, p3: Vector2, thick: float32, color: Color)`
- `rl.drawSplineSegmentCatmullRom(p1: Vector2, p2: Vector2, p3: Vector2, p4: Vector2, thick: float32, color: Color)`
- `rl.drawSplineSegmentLinear(p1: Vector2, p2: Vector2, thick: float32, color: Color)`
- `rl.drawTextCodepoint(font: Font, codepoint: Rune, position: Vector2, fontSize: float32, tint: Color)`
- `rl.drawTextCodepoints(font: Font, codepoints: openArray[Rune], position: Vector2, fontSize: float32, spacing: float32, tint: Color)`
- `rl.drawText(font: Font, text: string, position: Vector2, fontSize: float32, spacing: float32, tint: Color)`
- `rl.drawText(font: Font, text: string, position: Vector2, origin: Vector2, rotation: float32, fontSize: float32, spacing: float32, tint: Color)`
- `rl.drawText(text: string, posX: int32, posY: int32, fontSize: int32, color: Color)`
- `rl.drawTexture(texture: Texture2D, nPatchInfo: NPatchInfo, dstrec: Rectangle, origin: Vector2, rotation: float32, tint: Color)`
- `rl.drawTexture(texture: Texture2D, posX: int32, posY: int32, tint: Color)`
- `rl.drawTexture(texture: Texture2D, position: Vector2, rotation: float32, scale: float32, tint: Color)`
- `rl.drawTexture(texture: Texture2D, position: Vector2, tint: Color)`
- `rl.drawTexture(texture: Texture2D, rec: Rectangle, position: Vector2, tint: Color)`
- `rl.drawTexture(texture: Texture2D, srcrec: Rectangle, dstrec: Rectangle, origin: Vector2, rotation: float32, tint: Color)`
- `rl.drawTriangle3D(v1: Vector3, v2: Vector3, v3: Vector3, color: Color)`
- `rl.drawTriangleFan(points: openArray[Vector2], color: Color)`
- `rl.drawTriangleGradient(v1: Vector2, v2: Vector2, v3: Vector2, c1: Color, c2: Color, c3: Color)`
- `rl.drawTriangleLines(v1: Vector2, v2: Vector2, v3: Vector2, color: Color)`
- `rl.drawTriangleLines(v1: Vector2, v2: Vector2, v3: Vector2, thick: float32, color: Color)`
- `rl.drawTriangleStrip3D(points: openArray[Vector3], color: Color)`
- `rl.drawTriangleStrip(points: openArray[Vector2], color: Color)`
- `rl.drawTriangle(v1: Vector2, v2: Vector2, v3: Vector2, color: Color)`
- `rl.enableCursor()`
- `rl.enableEventWaiting()`
- `rl.endBlendMode()`
- `rl.endMode2D()`
- `rl.endMode3D()`
- `rl.endScissorMode()`
- `rl.endShaderMode()`
- `rl.endTextureMode()`
- `rl.endVrStereoMode()`
- `rl.exportAutomationEventList(list: AutomationEventList, fileName: string): bool` (parameter list is a AutomationEventList)
- `rl.exportDataAsCode(data: openArray[byte], fileName: string): bool`
- `rl.exportFontAsCode(font: Font, fileName: string): bool`
- `rl.exportImageAsCode(image: Image, fileName: string): bool`
- `rl.exportImageToMemory(image: Image, fileType: string): RArray[uint8]`
- `rl.exportImage(image: Image, fileName: string): bool`
- `rl.exportMeshAsCode(mesh: Mesh, fileName: string): bool`
- `rl.exportMesh(mesh: Mesh, fileName: string): bool`
- `rl.exportWaveAsCode(wave: Wave, fileName: string): bool`
- `rl.exportWave(wave: Wave, fileName: string): bool`
- `rl.fade(color: Color, alpha: float32): Color`
- `rl.genImageCellular(width: int32, height: int32, tileSize: int32): Image`
- `rl.genImageChecked(width: int32, height: int32, checksX: int32, checksY: int32, col1: Color, col2: Color): Image`
- `rl.genImageColor(width: int32, height: int32, color: Color): Image`
- `rl.genImageFontAtlas(chars: openArray[GlyphInfo], recs: var RArray[Rectangle], fontSize: int32, padding: int32, packMethod: int32): Image`
- `rl.genImageGradientLinear(width: int32, height: int32, direction: int32, start: Color, end: Color): Image`
- `rl.genImageGradientRadial(width: int32, height: int32, density: float32, inner: Color, outer: Color): Image`
- `rl.genImageGradientSquare(width: int32, height: int32, density: float32, inner: Color, outer: Color): Image`
- `rl.genImagePerlinNoise(width: int32, height: int32, offsetX: int32, offsetY: int32, scale: float32): Image`
- `rl.genImageText(width: int32, height: int32, text: string): Image`
- `rl.genImageWhiteNoise(width: int32, height: int32, factor: float32): Image`
- `rl.genMeshCone(radius: float32, height: float32, slices: int32): Mesh`
- `rl.genMeshCube(width: float32, height: float32, length: float32): Mesh`
- `rl.genMeshCubicmap(cubicmap: Image, cubeSize: Vector3): Mesh`
- `rl.genMeshCylinder(radius: float32, height: float32, slices: int32): Mesh`
- `rl.genMeshHeightmap(heightmap: Image, size: Vector3): Mesh`
- `rl.genMeshHemiSphere(radius: float32, rings: int32, slices: int32): Mesh`
- `rl.genMeshKnot(radius: float32, size: float32, radSeg: int32, sides: int32): Mesh`
- `rl.genMeshPlane(width: float32, length: float32, resX: int32, resZ: int32): Mesh`
- `rl.genMeshPoly(sides: int32, radius: float32): Mesh`
- `rl.genMeshSphere(radius: float32, rings: int32, slices: int32): Mesh`
- `rl.genMeshTangents(mesh: var Mesh)`
- `rl.genMeshTorus(radius: float32, size: float32, radSeg: int32, sides: int32): Mesh`
- `rl.genTextureMipmaps(texture: var Texture2D)`
- `rl.getCameraMatrix2D(camera: Camera2D): Matrix`
- `rl.getCameraMatrix(camera: Camera): Matrix`
- `rl.getCharPressed(): int32`
- `rl.getClipboardImage(): Image`
- `rl.getClipboardText(): string`
- `rl.getCollisionRec(rec1: Rectangle, rec2: Rectangle): Rectangle`
- `rl.getColor(hexValue: uint32): Color`
- `rl.getCurrentMonitor(): int32`
- `rl.getDroppedFiles(): seq[string]`
- `rl.getFPS(): int32`
- `rl.getFontDefault(): Font`
- `rl.getFrameTime(): float32`
- `rl.getGamepadAxisCount(gamepad: int32): int32`
- `rl.getGamepadAxisMovement(gamepad: int32, axis: GamepadAxis): float32`
- `rl.getGamepadButtonPressed(): GamepadButton`
- `rl.getGamepadName(gamepad: int32): string`
- `rl.getGestureDetected(): Gesture`
- `rl.getGestureDragAngle(): float32`
- `rl.getGestureDragVector(): Vector2`
- `rl.getGestureHoldDuration(): float32`
- `rl.getGesturePinchAngle(): float32`
- `rl.getGesturePinchVector(): Vector2`
- `rl.getGlyphAtlasRec(font: Font, codepoint: Rune): Rectangle`
- `rl.getGlyphIndex(font: Font, codepoint: Rune): int32`
- `rl.getGlyphInfo(font: Font, codepoint: Rune): GlyphInfo`
- `rl.getImageAlphaBorder(image: Image, threshold: float32): Rectangle`
- `rl.getImageColor(image: Image, x: int32, y: int32): Color`
- `rl.getKeyName(key: int32): string`
- `rl.getKeyPressed(): KeyboardKey`
- `rl.getMasterVolume(): float32`
- `rl.getMeshBoundingBox(mesh: Mesh): BoundingBox`
- `rl.getModelBoundingBox(model: Model): BoundingBox`
- `rl.getMonitorCount(): int32`
- `rl.getMonitorHeight(monitor: int32): int32`
- `rl.getMonitorName(monitor: int32): string`
- `rl.getMonitorPhysicalHeight(monitor: int32): int32`
- `rl.getMonitorPhysicalWidth(monitor: int32): int32`
- `rl.getMonitorPosition(monitor: int32): Vector2`
- `rl.getMonitorRefreshRate(monitor: int32): int32`
- `rl.getMonitorWidth(monitor: int32): int32`
- `rl.getMouseDelta(): Vector2`
- `rl.getMousePosition(): Vector2`
- `rl.getMouseWheelMoveV(): Vector2`
- `rl.getMouseWheelMove(): float32`
- `rl.getMouseX(): int32`
- `rl.getMouseY(): int32`
- `rl.getMusicTimeLength(music: Music): float32`
- `rl.getMusicTimePlayed(music: Music): float32`
- `rl.getPixelDataSize(width: int32, height: int32, format: PixelFormat): int32`
- `rl.getRayCollisionBox(ray: Ray, box: BoundingBox): RayCollision`
- `rl.getRayCollisionMesh(ray: Ray, mesh: Mesh, transform: Matrix): RayCollision`
- `rl.getRayCollisionQuad(ray: Ray, p1: Vector3, p2: Vector3, p3: Vector3, p4: Vector3): RayCollision`
- `rl.getRayCollisionSphere(ray: Ray, center: Vector3, radius: float32): RayCollision`
- `rl.getRayCollisionTriangle(ray: Ray, p1: Vector3, p2: Vector3, p3: Vector3): RayCollision`
- `rl.getRenderHeight(): int32`
- `rl.getRenderWidth(): int32`
- `rl.getScreenHeight(): int32`
- `rl.getScreenToWorld2D(position: Vector2, camera: Camera2D): Vector2`
- `rl.getScreenToWorldRay(position: Vector2, camera: Camera): Ray`
- `rl.getScreenToWorldRay(position: Vector2, camera: Camera, width: int32, height: int32): Ray`
- `rl.getScreenWidth(): int32`
- `rl.getShaderLocationAttrib(shader: Shader, attribName: string): ShaderLocation`
- `rl.getShaderLocation(shader: Shader, uniformName: string): ShaderLocation`
- `rl.getShapesTextureRectangle(): Rectangle`
- `rl.getShapesTexture(): Texture2D`
- `rl.getSplinePointBasis(p1: Vector2, p2: Vector2, p3: Vector2, p4: Vector2, t: float32): Vector2`
- `rl.getSplinePointBezierCubic(p1: Vector2, c2: Vector2, c3: Vector2, p4: Vector2, t: float32): Vector2`
- `rl.getSplinePointBezierQuadratic(p1: Vector2, c2: Vector2, p3: Vector2, t: float32): Vector2`
- `rl.getSplinePointCatmullRom(p1: Vector2, p2: Vector2, p3: Vector2, p4: Vector2, t: float32): Vector2`
- `rl.getSplinePointLinear(startPos: Vector2, endPos: Vector2, t: float32): Vector2`
- `rl.getTime(): float64`
- `rl.getTouchPointCount(): int32`
- `rl.getTouchPointId(index: int32): int32`
- `rl.getTouchPosition(index: int32): Vector2`
- `rl.getTouchX(): int32`
- `rl.getTouchY(): int32`
- `rl.getWindowHandle(): pointer` (the result is a pointer)
- `rl.getWindowPosition(): Vector2`
- `rl.getWindowScaleDPI(): Vector2`
- `rl.getWorldToScreen2D(position: Vector2, camera: Camera2D): Vector2`
- `rl.getWorldToScreen(position: Vector3, camera: Camera): Vector2`
- `rl.getWorldToScreen(position: Vector3, camera: Camera, width: int32, height: int32): Vector2`
- `rl.glyphCount(x: Font): int32`
- `rl.hideCursor()`
- `rl.imageAlphaClear(image: var Image, color: Color, threshold: float32)`
- `rl.imageAlphaCrop(image: var Image, threshold: float32)`
- `rl.imageAlphaMask(image: var Image, alphaMask: Image)`
- `rl.imageAlphaPremultiply(image: var Image)`
- `rl.imageBlurGaussian(image: var Image, blurSize: int32)`
- `rl.imageClearBackground(dst: var Image, color: Color)`
- `rl.imageColorBrightness(image: var Image, brightness: int32)`
- `rl.imageColorContrast(image: var Image, contrast: int32)`
- `rl.imageColorGrayscale(image: var Image)`
- `rl.imageColorInvert(image: var Image)`
- `rl.imageColorReplace(image: var Image, color: Color, replace: Color)`
- `rl.imageColorTint(image: var Image, color: Color)`
- `rl.imageCopy(image: Image): Image`
- `rl.imageCrop(image: var Image, crop: Rectangle)`
- `rl.imageDither(image: var Image, rBpp: int32, gBpp: int32, bBpp: int32, aBpp: int32)`
- `rl.imageDrawCircleGradient(dst: var Image, center: Vector2, radius: float32, inner: Color, outer: Color)`
- `rl.imageDrawCircleLines(dst: var Image, center: Vector2, radius: int32, color: Color)`
- `rl.imageDrawCircleLines(dst: var Image, centerX: int32, centerY: int32, radius: int32, color: Color)`
- `rl.imageDrawCircle(dst: var Image, center: Vector2, radius: int32, color: Color)`
- `rl.imageDrawCircle(dst: var Image, centerX: int32, centerY: int32, radius: int32, color: Color)`
- `rl.imageDrawImage(dst: var Image, src: Image, posX: int32, posY: int32, tint: Color)`
- `rl.imageDrawImage(dst: var Image, src: Image, position: Vector2, rotation: float32, scale: float32, tint: Color)`
- `rl.imageDrawImage(dst: var Image, src: Image, srcRec: Rectangle, dstRec: Rectangle, origin: Vector2, rotation: float32, tint: Color)`
- `rl.imageDrawImage(dst: var Image, src: Image, srcRec: Rectangle, position: Vector2, tint: Color)`
- `rl.imageDrawLineStrip(dst: var Image, points: openArray[Vector2], color: Color)`
- `rl.imageDrawLine(dst: var Image, start: Vector2, end: Vector2, color: Color)`
- `rl.imageDrawLine(dst: var Image, start: Vector2, end: Vector2, thick: int32, color: Color)`
- `rl.imageDrawLine(dst: var Image, startPosX: int32, startPosY: int32, endPosX: int32, endPosY: int32, color: Color)`
- `rl.imageDrawPixel(dst: var Image, posX: int32, posY: int32, color: Color)`
- `rl.imageDrawPixel(dst: var Image, position: Vector2, color: Color)`
- `rl.imageDrawRectangleGradient(dst: var Image, rec: Rectangle, col1: Color, col2: Color, col3: Color, col4: Color)`
- `rl.imageDrawRectangleLines(dst: var Image, posX: int32, posY: int32, width: int32, height: int32, color: Color)`
- `rl.imageDrawRectangleLines(dst: var Image, rec: Rectangle, thick: int32, color: Color)`
- `rl.imageDrawRectangle(dst: var Image, posX: int32, posY: int32, width: int32, height: int32, color: Color)`
- `rl.imageDrawRectangle(dst: var Image, position: Vector2, size: Vector2, color: Color)`
- `rl.imageDrawRectangle(dst: var Image, rec: Rectangle, color: Color)`
- `rl.imageDrawRectangle(dst: var Image, rec: Rectangle, origin: Vector2, rotation: float32, color: Color)`
- `rl.imageDrawText(dst: var Image, font: Font, text: string, position: Vector2, fontSize: float32, spacing: float32, tint: Color)`
- `rl.imageDrawText(dst: var Image, font: Font, text: string, position: Vector2, origin: Vector2, rotation: float32, fontSize: float32, spacing: float32, tint: Color)`
- `rl.imageDrawText(dst: var Image, text: string, posX: int32, posY: int32, fontSize: int32, color: Color)`
- `rl.imageDrawTriangleFan(dst: var Image, points: openArray[Vector2], color: Color)`
- `rl.imageDrawTriangleGradient(dst: var Image, v1: Vector2, v2: Vector2, v3: Vector2, c1: Color, c2: Color, c3: Color)`
- `rl.imageDrawTriangleLines(dst: var Image, v1: Vector2, v2: Vector2, v3: Vector2, color: Color)`
- `rl.imageDrawTriangleStrip(dst: var Image, points: openArray[Vector2], color: Color)`
- `rl.imageDrawTriangle(dst: var Image, v1: Vector2, v2: Vector2, v3: Vector2, color: Color)`
- `rl.imageFlipHorizontal(image: var Image)`
- `rl.imageFlipVertical(image: var Image)`
- `rl.imageFormat(image: var Image, newFormat: PixelFormat)`
- `rl.imageFromChannel(image: Image, selectedChannel: int32): Image`
- `rl.imageFromImage(image: Image, rec: Rectangle): Image`
- `rl.imageKernelConvolution(image: var Image, kernel: openArray[float32])`
- `rl.imageMipmaps(image: var Image)`
- `rl.imageResizeCanvas(image: var Image, newWidth: int32, newHeight: int32, offsetX: int32, offsetY: int32, fill: Color)`
- `rl.imageResizeNN(image: var Image, newWidth: int32, newHeight: int32)`
- `rl.imageResize(image: var Image, newWidth: int32, newHeight: int32)`
- `rl.imageRotateCCW(image: var Image)`
- `rl.imageRotateCW(image: var Image)`
- `rl.imageRotate(image: var Image, degrees: int32)`
- `rl.imageText(font: Font, text: string, fontSize: float32, spacing: float32, tint: Color): Image`
- `rl.imageText(text: string, fontSize: int32, color: Color): Image`
- `rl.imageToPOT(image: var Image, fill: Color)`
- `rl.isAudioDeviceReady(): bool`
- `rl.isAudioStreamPlaying(stream: AudioStream): bool`
- `rl.isAudioStreamProcessed(stream: AudioStream): bool`
- `rl.isAudioStreamValid(stream: AudioStream): bool`
- `rl.isCursorHidden(): bool`
- `rl.isCursorOnScreen(): bool`
- `rl.isFileDropped(): bool`
- `rl.isFontValid(font: Font): bool`
- `rl.isGamepadAvailable(gamepad: int32): bool`
- `rl.isGamepadButtonDown(gamepad: int32, button: GamepadButton): bool`
- `rl.isGamepadButtonPressed(gamepad: int32, button: GamepadButton): bool`
- `rl.isGamepadButtonReleased(gamepad: int32, button: GamepadButton): bool`
- `rl.isGamepadButtonUp(gamepad: int32, button: GamepadButton): bool`
- `rl.isGestureDetected(gesture: Gesture): bool`
- `rl.isImageValid(image: Image): bool`
- `rl.isKeyDown(key: KeyboardKey): bool`
- `rl.isKeyPressedRepeat(key: KeyboardKey): bool`
- `rl.isKeyPressed(key: KeyboardKey): bool`
- `rl.isKeyReleased(key: KeyboardKey): bool`
- `rl.isKeyUp(key: KeyboardKey): bool`
- `rl.isMaterialValid(material: Material): bool`
- `rl.isModelAnimationValid(model: Model, anim: ModelAnimation): bool`
- `rl.isModelValid(model: Model): bool`
- `rl.isMouseButtonDown(button: MouseButton): bool`
- `rl.isMouseButtonPressed(button: MouseButton): bool`
- `rl.isMouseButtonReleased(button: MouseButton): bool`
- `rl.isMouseButtonUp(button: MouseButton): bool`
- `rl.isMusicStreamPlaying(music: Music): bool`
- `rl.isMusicValid(music: Music): bool`
- `rl.isRenderTextureValid(target: RenderTexture2D): bool`
- `rl.isShaderValid(shader: Shader): bool`
- `rl.isSoundPlaying(sound: Sound): bool`
- `rl.isSoundValid(sound: Sound): bool`
- `rl.isTextureValid(texture: Texture2D): bool`
- `rl.isWaveValid(wave: Wave): bool`
- `rl.isWindowFocused(): bool`
- `rl.isWindowFullscreen(): bool`
- `rl.isWindowHidden(): bool`
- `rl.isWindowMaximized(): bool`
- `rl.isWindowMinimized(): bool`
- `rl.isWindowReady(): bool`
- `rl.isWindowResized(): bool`
- `rl.isWindowState(flag: ConfigFlags): bool`
- `rl.keyframeCount(x: ModelAnimation): int32`
- `rl.len(x: AutomationEventList): int` (parameter x is a AutomationEventList)
- `rl.loadAudioStream(sampleRate: uint32, sampleSize: uint32, channels: uint32): AudioStream`
- `rl.loadAutomationEventList(fileName: string): AutomationEventList` (the result is a AutomationEventList)
- `rl.loadFontData(fileData: openArray[uint8], fontSize: int32, codepoints: openArray[int32], type: FontType): RArray[GlyphInfo]`
- `rl.loadFontData(fileData: openArray[uint8], fontSize: int32, glyphCount: int32, type: FontType): RArray[GlyphInfo]`
- `rl.loadFontFromData(chars: RArray[GlyphInfo], baseSize: int32, padding: int32, packMethod: int32): Font`
- `rl.loadFontFromImage(image: Image, key: Color, firstChar: int32): Font`
- `rl.loadFontFromMemory(fileType: string, fileData: openArray[uint8], fontSize: int32, codepoints: openArray[int32]): Font`
- `rl.loadFontFromMemory(fileType: string, fileData: openArray[uint8], fontSize: int32, glyphCount: int32): Font`
- `rl.loadFont(fileName: string): Font`
- `rl.loadFont(fileName: string, fontSize: int32, codepoints: openArray[int32]): Font`
- `rl.loadFont(fileName: string, fontSize: int32, glyphCount: int32): Font`
- `rl.loadImageAnimFromMemory(fileType: string, fileData: openArray[uint8], frames: var int32): Image`
- `rl.loadImageAnim(fileName: string, frames: var int32): Image`
- `rl.loadImageColors(image: Image): RArray[Color]`
- `rl.loadImageFromMemory(fileType: string, fileData: openArray[uint8]): Image`
- `rl.loadImageFromScreen(): Image`
- `rl.loadImageFromTexture(texture: Texture2D): Image`
- `rl.loadImagePalette(image: Image, maxPaletteSize: int32): RArray[Color]`
- `rl.loadImageRaw(fileName: string, width: int32, height: int32, format: PixelFormat, headerSize: int32): Image`
- `rl.loadImage(fileName: string): Image`
- `rl.loadMaterialDefault(): Material`
- `rl.loadMaterials(fileName: string): RArray[Material]` (the result is a RArray[Material])
- `rl.loadModelAnimations(fileName: string): RArray[ModelAnimation]` (the result is a RArray[ModelAnimation])
- `rl.loadModelFromMesh(mesh: Mesh): ModelFromMesh` (the result is a ModelFromMesh)
- `rl.loadModel(fileName: string): Model`
- `rl.loadMusicStreamFromMemory(fileType: string, data: openArray[uint8]): Music`
- `rl.loadMusicStream(fileName: string): Music`
- `rl.loadRenderTexture(width: int32, height: int32): RenderTexture2D`
- `rl.loadRenderTexture(width: int32, height: int32, format: PixelFormat): RenderTexture2D`
- `rl.loadShaderFromMemory(vsCode: string, fsCode: string): Shader`
- `rl.loadShader(vsFileName: string, fsFileName: string): Shader`
- `rl.loadSoundAlias(source: Sound): SoundAlias` (the result is a SoundAlias)
- `rl.loadSoundFromWave(wave: Wave): Sound`
- `rl.loadSound(fileName: string): Sound`
- `rl.loadTextureCubemap(image: Image, layout: CubemapLayout): TextureCubemap`
- `rl.loadTextureFromImage(image: Image): Texture2D`
- `rl.loadTexture(fileName: string): Texture2D`
- `rl.loadVrStereoConfig(device: VrDeviceInfo): VrStereoConfig`
- `rl.loadWaveFromMemory(fileType: string, fileData: openArray[uint8]): Wave`
- `rl.loadWaveSamples(wave: Wave): RArray[float32]`
- `rl.loadWave(fileName: string): Wave`
- `rl.materialCount(x: Model): int32`
- `rl.maximizeWindow()`
- `rl.measureTextCodepoints(font: Font, codepoints: openArray[Rune], fontSize: float32, spacing: float32): Vector2`
- `rl.measureText(font: Font, text: string, fontSize: float32, spacing: float32): Vector2`
- `rl.measureText(text: string, fontSize: int32): int32`
- `rl.meshCount(x: Model): int32`
- `rl.minimizeWindow()`
- `rl.pauseAudioStream(stream: AudioStream)`
- `rl.pauseMusicStream(music: Music)`
- `rl.pauseSound(sound: Sound)`
- `rl.playAudioStream(stream: AudioStream)`
- `rl.playAutomationEvent(event: AutomationEvent)`
- `rl.playMusicStream(music: Music)`
- `rl.playSound(sound: Sound)`
- `rl.restoreWindow()`
- `rl.resumeAudioStream(stream: AudioStream)`
- `rl.resumeMusicStream(music: Music)`
- `rl.resumeSound(sound: Sound)`
- `rl.seekMusicStream(music: Music, position: float32)`
- `rl.setAudioStreamBufferSizeDefault(size: int32)`
- `rl.setAudioStreamPan(stream: AudioStream, pan: float32)`
- `rl.setAudioStreamPitch(stream: AudioStream, pitch: float32)`
- `rl.setAudioStreamVolume(stream: AudioStream, volume: float32)`
- `rl.setAutomationEventBaseFrame(frame: int32)`
- `rl.setAutomationEventList(list: var AutomationEventList)`
- `rl.setClipboardText(text: string)`
- `rl.setConfigFlags(flags: Flags[ConfigFlags])`
- `rl.setExitKey(key: KeyboardKey)`
- `rl.setGamepadMappings(mappings: string): int32`
- `rl.setGamepadVibration(gamepad: int32, leftMotor: float32, rightMotor: float32, duration: float32)`
- `rl.setGesturesEnabled(flags: Flags[Gesture])`
- `rl.setMasterVolume(volume: float32)`
- `rl.setMouseCursor(cursor: MouseCursor)`
- `rl.setMouseOffset(offsetX: int32, offsetY: int32)`
- `rl.setMousePosition(x: int32, y: int32)`
- `rl.setMouseScale(scaleX: float32, scaleY: float32)`
- `rl.setMusicPan(music: Music, pan: float32)`
- `rl.setMusicPitch(music: Music, pitch: float32)`
- `rl.setMusicVolume(music: Music, volume: float32)`
- `rl.setShaderValueMatrix(shader: Shader, locIndex: ShaderLocation, mat: Matrix)`
- `rl.setShaderValueTexture(shader: Shader, locIndex: ShaderLocation, texture: Texture2D)`
- `rl.setShapesTexture(texture: Texture2D, rec: Rectangle)`
- `rl.setSoundPan(sound: Sound, pan: float32)`
- `rl.setSoundPitch(sound: Sound, pitch: float32)`
- `rl.setSoundVolume(sound: Sound, volume: float32)`
- `rl.setTargetFPS(fps: int32)`
- `rl.setTextLineSpacing(spacing: int32)`
- `rl.setTextureFilter(texture: Texture2D, filter: TextureFilter)`
- `rl.setTextureWrap(texture: Texture2D, wrap: TextureWrap)`
- `rl.setTraceLogLevel(logLevel: TraceLogLevel)`
- `rl.setWindowFocused()`
- `rl.setWindowIcon(image: Image)`
- `rl.setWindowIcons(images: openArray[Image])`
- `rl.setWindowMaxSize(width: int32, height: int32)`
- `rl.setWindowMinSize(width: int32, height: int32)`
- `rl.setWindowMonitor(monitor: int32)`
- `rl.setWindowOpacity(opacity: float32)`
- `rl.setWindowPosition(x: int32, y: int32)`
- `rl.setWindowSize(width: int32, height: int32)`
- `rl.setWindowState(flags: Flags[ConfigFlags])`
- `rl.setWindowTitle(title: string)`
- `rl.showCursor()`
- `rl.startAutomationEventRecording()`
- `rl.stopAudioStream(stream: AudioStream)`
- `rl.stopAutomationEventRecording()`
- `rl.stopMusicStream(music: Music)`
- `rl.stopSound(sound: Sound)`
- `rl.takeScreenshot(fileName: string)`
- `rl.toWeakImage(data: openArray[byte], width: int32, height: int32, format: PixelFormat): WeakImage`
- `rl.toWeakWave(data: openArray[byte], frameCount: uint32, sampleRate: uint32, sampleSize: uint32, channels: uint32): WeakWave`
- `rl.toggleBorderlessWindowed()`
- `rl.toggleFullscreen()`
- `rl.traceLog(logLevel: TraceLogLevel, text: cstring)` (parameter text is a cstring)
- `rl.triangleCount(x: Mesh): int32`
- `rl.unloadAutomationEventList(list: AutomationEventList)` (parameter list is a AutomationEventList)
- `rl.updateCamera(camera: var Camera, mode: CameraMode)`
- `rl.updateCamera(camera: var Camera, movement: Vector3, rotation: Vector3, zoom: float32)`
- `rl.updateModelAnimation(model: Model, anim: ModelAnimation, frame: float32)`
- `rl.updateModelAnimation(model: Model, animA: ModelAnimation, frameA: float32, animB: ModelAnimation, frameB: float32, blend: float32)`
- `rl.updateMusicStream(music: Music)`
- `rl.updateTexture(texture: Texture2D, image: Image)`
- `rl.uploadMesh(mesh: var Mesh, dynamic: bool)`
- `rl.vertexCount(x: Mesh): int32`
- `rl.waitTime(seconds: float64)`
- `rl.waveCopy(wave: Wave): Wave`
- `rl.waveCrop(wave: var Wave, initFrame: int32, finalFrame: int32)`
- `rl.waveFormat(wave: var Wave, sampleRate: int32, sampleSize: int32, channels: int32)`
- `rl.windowShouldClose(): bool`
- `rl.gl.activeDrawBuffers(count: int32)`
- `rl.gl.activeTextureSlot(slot: int32)`
- `rl.gl.bindFramebuffer(target: FramebufferTarget, framebuffer: uint32)`
- `rl.gl.bindImageTexture(id: uint32, index: uint32, format: PixelFormat, readonly: bool)`
- `rl.gl.bindShaderBuffer(id: uint32, index: uint32)`
- `rl.gl.blitFramebuffer(srcX: int32, srcY: int32, srcWidth: int32, srcHeight: int32, dstX: int32, dstY: int32, dstWidth: int32, dstHeight: int32, bufferMask: int32)`
- `rl.gl.bufferCount(x: RenderBatch): int32` (parameter x is a RenderBatch)
- `rl.gl.checkErrors()`
- `rl.gl.checkRenderBatchLimit(vCount: int32): bool`
- `rl.gl.clearColor(r: uint8, g: uint8, b: uint8, a: uint8)`
- `rl.gl.clearScreenBuffers()`
- `rl.gl.color3f(x: float32, y: float32, z: float32)`
- `rl.gl.color4f(x: float32, y: float32, z: float32, w: float32)`
- `rl.gl.color4ub(r: uint8, g: uint8, b: uint8, a: uint8)`
- `rl.gl.colorMask(r: bool, g: bool, b: bool, a: bool)`
- `rl.gl.computeShaderDispatch(groupX: uint32, groupY: uint32, groupZ: uint32)`
- `rl.gl.copyFramebuffer(x: int32, y: int32, width: int32, height: int32, format: int32, pixels: pointer)` (parameter pixels is a pointer)
- `rl.gl.copyShaderBuffer(destId: uint32, srcId: uint32, destOffset: uint32, srcOffset: uint32, count: uint32)`
- `rl.gl.cubemapParameters(id: uint32, param: int32, value: int32)`
- `rl.gl.disableBackfaceCulling()`
- `rl.gl.disableColorBlend()`
- `rl.gl.disableDepthMask()`
- `rl.gl.disableDepthTest()`
- `rl.gl.disableFramebuffer()`
- `rl.gl.disablePointMode()`
- `rl.gl.disableScissorTest()`
- `rl.gl.disableShader()`
- `rl.gl.disableSmoothLines()`
- `rl.gl.disableStatePointer(vertexAttribType: int32)`
- `rl.gl.disableStereoRender()`
- `rl.gl.disableTextureCubemap()`
- `rl.gl.disableTexture()`
- `rl.gl.disableVertexArray()`
- `rl.gl.disableVertexAttribute(index: uint32)`
- `rl.gl.disableVertexBufferElement()`
- `rl.gl.disableVertexBuffer()`
- `rl.gl.disableWireMode()`
- `rl.gl.drawRenderBatchActive()`
- `rl.gl.drawRenderBatch(batch: var RenderBatch)`
- `rl.gl.drawVertexArrayElementsInstanced(offset: int32, count: int32, buffer: pointer, instances: int32)` (parameter buffer is a pointer)
- `rl.gl.drawVertexArrayElements(offset: int32, count: int32, buffer: pointer)` (parameter buffer is a pointer)
- `rl.gl.drawVertexArrayInstanced(offset: int32, count: int32, instances: int32)`
- `rl.gl.drawVertexArray(offset: int32, count: int32)`
- `rl.gl.elementCount(x: VertexBuffer): int32` (parameter x is a VertexBuffer)
- `rl.gl.enableBackfaceCulling()`
- `rl.gl.enableColorBlend()`
- `rl.gl.enableDepthMask()`
- `rl.gl.enableDepthTest()`
- `rl.gl.enableFramebuffer(id: uint32)`
- `rl.gl.enablePointMode()`
- `rl.gl.enableScissorTest()`
- `rl.gl.enableShader(id: uint32)`
- `rl.gl.enableSmoothLines()`
- `rl.gl.enableStatePointer(vertexAttribType: int32, buffer: pointer)` (parameter buffer is a pointer)
- `rl.gl.enableStereoRender()`
- `rl.gl.enableTextureCubemap(id: uint32)`
- `rl.gl.enableTexture(id: uint32)`
- `rl.gl.enableVertexArray(vaoId: uint32): bool`
- `rl.gl.enableVertexAttribute(index: uint32)`
- `rl.gl.enableVertexBufferElement(id: uint32)`
- `rl.gl.enableVertexBuffer(id: uint32)`
- `rl.gl.enableWireMode()`
- `rl.gl.framebufferAttach(id: uint32, texId: uint32, attachType: FramebufferAttachType, texType: FramebufferAttachTextureType, mipLevel: int32)`
- `rl.gl.framebufferComplete(id: uint32): bool`
- `rl.gl.frustum(left: float64, right: float64, bottom: float64, top: float64, znear: float64, zfar: float64)`
- `rl.gl.genTextureMipmaps(id: uint32, width: int32, height: int32, format: PixelFormat, mipmaps: var int32)`
- `rl.gl.getActiveFramebuffer(): uint32`
- `rl.gl.getCullDistanceFar(): float64`
- `rl.gl.getCullDistanceNear(): float64`
- `rl.gl.getFramebufferHeight(): int32`
- `rl.gl.getFramebufferWidth(): int32`
- `rl.gl.getGlTextureFormats(format: PixelFormat, glInternalFormat: var uint32, glFormat: var uint32, glType: var uint32)`
- `rl.gl.getLineWidth(): float32`
- `rl.gl.getLocationAttrib(id: uint32, attribName: string): ShaderLocation`
- `rl.gl.getLocationUniform(id: uint32, uniformName: string): ShaderLocation`
- `rl.gl.getMatrixModelview(): Matrix`
- `rl.gl.getMatrixProjectionStereo(eye: int32): Matrix`
- `rl.gl.getMatrixProjection(): Matrix`
- `rl.gl.getMatrixTransform(): Matrix`
- `rl.gl.getMatrixViewOffsetStereo(eye: int32): Matrix`
- `rl.gl.getPixelFormatName(format: PixelFormat): string`
- `rl.gl.getPointSize(): float32`
- `rl.gl.getProcAddress(procName: string): pointer` (the result is a pointer)
- `rl.gl.getShaderBufferSize(id: uint32): uint32`
- `rl.gl.getShaderIdDefault(): uint32`
- `rl.gl.getShaderLocsDefault(): ShaderLocsPtr`
- `rl.gl.getTextureIdDefault(): uint32`
- `rl.gl.getVersion(): GlVersion`
- `rl.gl.isStereoRenderEnabled(): bool`
- `rl.gl.loadDrawCube()`
- `rl.gl.loadDrawQuad()`
- `rl.gl.loadExtensions(loader: rlglLoadProc)` (parameter loader is a rlglLoadProc)
- `rl.gl.loadFramebuffer(): uint32`
- `rl.gl.loadIdentity()`
- `rl.gl.loadRenderBatch(numBuffers: int32, bufferElements: int32): RenderBatch` (the result is a RenderBatch)
- `rl.gl.loadShaderBuffer(size: uint32, data: pointer, usageHint: BufferUsageHint): uint32` (parameter data is a pointer)
- `rl.gl.loadShaderProgramCompute(csId: uint32): uint32`
- `rl.gl.loadShaderProgram(vsCode: string, fsCode: string): uint32`
- `rl.gl.loadShaderProgram(vsId: uint32, fsId: uint32): uint32`
- `rl.gl.loadShader(code: string, type: ShaderType): uint32`
- `rl.gl.loadTextureCubemap(data: pointer, size: int32, format: PixelFormat, mipmapCount: int32): uint32` (parameter data is a pointer)
- `rl.gl.loadTextureDepth(width: int32, height: int32, useRenderBuffer: bool): uint32`
- `rl.gl.loadTexture(data: pointer, width: int32, height: int32, format: int32, mipmapCount: int32): uint32` (parameter data is a pointer)
- `rl.gl.loadVertexArray(): uint32`
- `rl.gl.loadVertexBufferElement(buffer: pointer, size: int32, dynamic: bool): uint32` (parameter buffer is a pointer)
- `rl.gl.loadVertexBuffer(buffer: pointer, size: int32, dynamic: bool): uint32` (parameter buffer is a pointer)
- `rl.gl.matrixMode(mode: MatrixMode)`
- `rl.gl.multMatrixf(matf: array[0 .. 15, float32])`
- `rl.gl.normal3f(x: float32, y: float32, z: float32)`
- `rl.gl.ortho(left: float64, right: float64, bottom: float64, top: float64, znear: float64, zfar: float64)`
- `rl.gl.popMatrix()`
- `rl.gl.pushMatrix()`
- `rl.gl.readShaderBuffer(id: uint32, dest: pointer, count: uint32, offset: uint32)` (parameter dest is a pointer)
- `rl.gl.readTexturePixels(id: uint32, width: int32, height: int32, format: PixelFormat): pointer` (the result is a pointer)
- `rl.gl.resizeFramebuffer(width: int32, height: int32)`
- `rl.gl.rlBegin(mode: DrawMode)`
- `rl.gl.rlEnd()`
- `rl.gl.rotatef(angle: float32, x: float32, y: float32, z: float32)`
- `rl.gl.scalef(x: float32, y: float32, z: float32)`
- `rl.gl.scissor(x: int32, y: int32, width: int32, height: int32)`
- `rl.gl.setBlendFactorsSeparate(glSrcRGB: BlendFactor, glDstRGB: BlendFactor, glSrcAlpha: BlendFactor, glDstAlpha: BlendFactor, glEqRGB: BlendFuncOrEq, glEqAlpha: BlendFuncOrEq)`
- `rl.gl.setBlendFactors(glSrcFactor: BlendFactor, glDstFactor: BlendFactor, glEquation: BlendFuncOrEq)`
- `rl.gl.setBlendMode(mode: BlendMode)`
- `rl.gl.setClipPlanes(nearPlane: float64, farPlane: float64)`
- `rl.gl.setCullFace(mode: CullMode)`
- `rl.gl.setFramebufferHeight(height: int32)`
- `rl.gl.setFramebufferWidth(width: int32)`
- `rl.gl.setLineWidth(width: float32)`
- `rl.gl.setMatrixModelview(view: Matrix)`
- `rl.gl.setMatrixProjectionStereo(right: Matrix, left: Matrix)`
- `rl.gl.setMatrixProjection(proj: Matrix)`
- `rl.gl.setMatrixViewOffsetStereo(right: Matrix, left: Matrix)`
- `rl.gl.setPointSize(size: float32)`
- `rl.gl.setRenderBatchActive(batch: var RenderBatch)`
- `rl.gl.setShader(id: uint32, locs: ShaderLocsPtr)`
- `rl.gl.setTexture(id: uint32)`
- `rl.gl.setUniformMatrices(locIndex: int32, mat: var Matrix, count: int32)`
- `rl.gl.setUniformMatrix(locIndex: ShaderLocation, mat: Matrix)`
- `rl.gl.setUniformSampler(locIndex: ShaderLocation, textureId: uint32)`
- `rl.gl.setUniform(locIndex: ShaderLocation, value: pointer, uniformType: ShaderUniformDataType, count: int32)` (parameter value is a pointer)
- `rl.gl.setVertexAttributeDefault(locIndex: ShaderLocation, value: pointer, attribType: ShaderAttributeDataType, count: int32)` (parameter value is a pointer)
- `rl.gl.setVertexAttributeDivisor(index: uint32, divisor: int32)`
- `rl.gl.setVertexAttribute(index: uint32, compSize: int32, type: GlType, normalized: bool, stride: int32, offset: int32)`
- `rl.gl.texCoord2f(x: float32, y: float32)`
- `rl.gl.textureParameters(id: uint32, param: TextureParameter, value: int32)`
- `rl.gl.translatef(x: float32, y: float32, z: float32)`
- `rl.gl.unloadFramebuffer(id: uint32)`
- `rl.gl.unloadShaderBuffer(ssboId: uint32)`
- `rl.gl.unloadShaderProgram(id: uint32)`
- `rl.gl.unloadShader(id: uint32)`
- `rl.gl.unloadTexture(id: uint32)`
- `rl.gl.unloadVertexArray(vaoId: uint32)`
- `rl.gl.unloadVertexBuffer(vboId: uint32)`
- `rl.gl.updateShaderBuffer(id: uint32, data: pointer, dataSize: uint32, offset: uint32)` (parameter data is a pointer)
- `rl.gl.updateTexture(id: uint32, offsetX: int32, offsetY: int32, width: int32, height: int32, format: PixelFormat, data: pointer)` (parameter data is a pointer)
- `rl.gl.updateVertexBufferElements(id: uint32, data: pointer, dataSize: int32, offset: int32)` (parameter data is a pointer)
- `rl.gl.updateVertexBuffer(bufferId: uint32, data: pointer, dataSize: int32, offset: int32)` (parameter data is a pointer)
- `rl.gl.vertex2f(x: float32, y: float32)`
- `rl.gl.vertex2i(x: int32, y: int32)`
- `rl.gl.vertex3f(x: float32, y: float32, z: float32)`
- `rl.gl.viewport(x: int32, y: int32, width: int32, height: int32)`

## engine.globals

The game's global state, read and written in place (`engine.globals.settings.musicVolume = 0.5`).

- `advancements: AdvancementProfile`
- `desktop: OSDesktop`
- `difficulty: GameDifficulty`
- `game: Game`
- `language: Language`
- `profileSlot: int`
- `roguelite: RogueliteProfile`
- `runStats: RunStatistics`
- `settings: Settings`
- `sound: SoundSystem`
- `stats: Statistics`
- `windows: WindowManager`
- `world3d: Game3D`
