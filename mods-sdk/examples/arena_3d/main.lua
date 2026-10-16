-- 3D Worlds: the two ways a mod works in 3D.
--
-- 1. Cube Siege, a whole game mode that lives in a 3D world. base = "3d"
--    launches straight into an EMPTY first-person world, and everything in it
--    is built by this script: the arena, the waves, the pickups, the weapon
--    and the HUD. Controls are the game's own: WASD, Space (double jump),
--    Shift, mouse, left click = shoot, R = reload, Esc = pause.
-- 2. Changes to the game's own 3D fight (wave boss 7, the Orbital Commander):
--    extra drones, a phase message and bonus damage on its satellites.
--
-- The world3d* hooks run for every 3D world, so each one first checks which
-- world it is in.

-- ============================================================ Cube Siege ====

local MODE = register.gamemode{
  id = "cube_siege",
  name = {en = "Cube Siege", es = "Asedio de Cubos"},
  description = {
    en = "First person. Survive six waves of cubes, drones and turrets with a shotgun.",
    es = "En primera persona. Sobrevive a seis oleadas de cubos, drones y torretas con una escopeta.",
  },
  base = "3d",
  resumable = false,
  -- onStart runs when the run starts, before the world's first frame: the
  -- place to hide parts of the built-in HUD (every run starts with all of it).
  onStart = function(game, resumed)
    hud.hide("player")   -- the HP / ammo box: we draw our own in world3dDrawHud
  end,
}

local TOTAL_WAVES = 6

-- Per-world state, replaced in world3dStart. Plain Lua values are fine here
-- (this is not saved; run.data below is).
local S = {}

local function siege(world) return world.modeKey == MODE end
local function say(en, es) return lang.current() == "es" and es or en end

local function buildArena(world)
  world3d.arena{theme = "empty", radius = 320,   -- radius also sets the walls: you stay inside 0.9 x radius
                sky = "#0b1020", floor = "#1c2333", wall = "#39435c"}
  -- An empty world has a solid floor at y = -9.5. A platform on top makes a
  -- coloured ground at y = 0 (w, h, d are FULL sizes). Stand the player on it,
  -- and bring them back there after a fall.
  world3d.platform{x = 0, y = -1, z = 0, w = 640, h = 2, d = 640, color = "#242c40"}
  world.spawnPos = {x = 0, y = 1, z = 0}
  world.player.pos = {x = 0, y = 1, z = 0}
  -- Four raised platforms, one that slides back and forth, and a jump pad
  for i = 0, 3 do
    local a = i / 4 * math.pi * 2 + math.pi / 4
    world3d.platform{x = math.cos(a) * 130, y = 14, z = math.sin(a) * 130, w = 40, h = 3, d = 40, color = "#3b5b8c"}
  end
  world3d.platform{x = 0, y = 34, z = -120, w = 34, h = 3, d = 34, color = "#8c5b3b", moving = true, moveSpeed = 0.5}
  world3d.platform{x = 60, y = 0.5, z = 60, w = 20, h = 1, d = 20, color = "#40ff80", jumpPad = true, jumpForce = 900}
end

local function tuneWeapon(world)
  local p = world.player
  p.maxHealth, p.health, p.speed = 100, 100, 80
  p.hitInvuln = 0.4              -- a short grace period after each hit
  -- A shotgun: many weak pellets in a cone, slow to fire, with a reload
  local w = p.weapon
  w.pellets = 8
  w.spread = 4                   -- degrees, each pellet strays up to this far
  w.damage = 12                  -- per pellet
  w.fireRate = 0.7               -- seconds between shots
  w.projectileSpeed, w.projectileRadius, w.projectileColor = 520, 1.1, "#ffd060"
  w.maxAmmo, w.ammo, w.reloadTime = 24, 24, 1.2
  S.baseDamage, S.baseRate = w.damage, w.fireRate
end

-- Entity fields: hp, radius, color, shape, size, speed, ai, contactDamage,
-- scoreValue, gravity, ... The built-in AI moves them; we only describe them.
local function spawnEnemy(kind, n)
  local a, r = math.random() * math.pi * 2, 150 + math.random() * 90
  local x, z = math.cos(a) * r, math.sin(a) * r   -- somewhere on a ring around the middle
  if kind == "chaser" then
    world3d.spawn{tag = "chaser", x = x, y = 4, z = z, hp = 30, radius = 4, shape = "cube", size = 7,
                  color = "#e04848", ai = "chase", speed = 22 + n * 2, contactDamage = 8, scoreValue = 10, gravity = true}
  elseif kind == "orbiter" then   -- flies, circles the player and shoots
    world3d.spawn{tag = "orbiter", x = x, y = 28, z = z, hp = 20, radius = 3.5, shape = "sphere",
                  color = "#40d0ff", ai = "orbit", orbitRadius = 70, speed = 34, fireInterval = 2.2,
                  projectileSpeed = 90, projectileDamage = 6, range = 220, scoreValue = 20, gravity = false}
  elseif kind == "turret" then    -- stands still, shoots, and blocks the way (solid)
    world3d.spawn{tag = "turret", x = x, y = 5, z = z, hp = 60, radius = 5, shape = "cylinder", size = 10,
                  color = "#c080ff", ai = "turret", fireInterval = 1.6, projectileSpeed = 110,
                  projectileDamage = 8, range = 260, scoreValue = 30, gravity = true, solid = true}
  else                            -- the brute: one tougher enemy every wave
    world3d.spawn{tag = "brute", x = x, y = 9, z = z, hp = 150 + n * 40, radius = 8, shape = "cube", size = 15,
                  color = "#ff8a30", ai = "chase", speed = 16, contactDamage = 20, scoreValue = 100, gravity = true}
  end
end

local function startWave(world)
  world.wave = world.wave + 1     -- world.wave and world.score are ours to use
  local n = world.wave
  for _ = 1, 3 + n * 2 do spawnEnemy("chaser", n) end
  for _ = 1, n - 1 do spawnEnemy("orbiter", n) end        -- from wave 2
  for _ = 1, (n - 1) // 2 do spawnEnemy("turret", n) end  -- from wave 3
  spawnEnemy("brute", n)
  -- run.data is saved with the run. A continued run rebuilds the world from
  -- scratch, so keep just enough to pick up again at this wave.
  run.data.wave, run.data.score, run.data.hp = world.wave, world.score, world.player.health
end

hooks.on("world3dStart", function(world, resumed)
  if not siege(world) then return end
  S = {overcharge = 0}
  buildArena(world)
  tuneWeapon(world)
  if resumed and run.data.wave then
    -- Continue: start the wave in progress again, with the score and HP the
    -- player had when it began.
    world.wave = math.floor(run.data.wave) - 1
    world.score = math.floor(run.data.score or 0)
    world.player.health = math.max(30, run.data.hp or 100)
  end
  S.nextAt = world.timeElapsed + 2
end)

hooks.on("world3dUpdate", function(world, dt)
  if not siege(world) or S.done then return end
  -- Overcharge (a pickup of ours): double damage for a few seconds
  if S.overcharge > 0 then
    S.overcharge = S.overcharge - dt
    if S.overcharge <= 0 then
      world.player.weapon.damage, world.player.weapon.fireRate = S.baseDamage, S.baseRate
    end
  end
  -- The waves: when the arena is empty, the next one comes 3 s later, and
  -- clearing the last one wins.
  if S.nextAt then
    if world.timeElapsed >= S.nextAt then
      S.nextAt = nil
      startWave(world)
    end
  elseif #world3d.entities() == 0 then
    if world.wave >= TOTAL_WAVES then
      S.done = true
      world3d.finish(true)          -- true = won (the victory screen)
    else
      S.nextAt = world.timeElapsed + 3
    end
  end
end)

-- Hooks can also just watch: returning nothing lets the shotgun fire
-- (returning true would cancel the shot).
hooks.on("world3dShoot", function(world)
  if siege(world) then world3d.shake(0.08) end
end)

-- Drops. The death hook can still read the dead entity (x, y, z, tag...).
hooks.on("world3dEntityDeath", function(e)
  if not siege(world3d.world) then return end
  local x, y, z, r = e.x, math.max(e.y, 3), e.z, math.random()
  if e.tag == "brute" or r < 0.05 then
    world3d.pickup{x = x, y = y, z = z, kind = "overcharge", value = 8, color = "#ff40ff", radius = 5}
  elseif r < 0.3 then
    world3d.pickup{x = x, y = y, z = z, kind = "health", value = 20}
  elseif r < 0.6 then
    world3d.pickup{x = x, y = y, z = z, kind = "ammo", value = 8}
  end
end)

-- Health and ammo have built-in effects. "overcharge" is ours, so we take it
-- ourselves: returning true means "taken, skip the built-in effect".
hooks.on("world3dPickup", function(pickup)
  if not siege(world3d.world) or pickup.kind ~= "overcharge" then return end
  local w = world3d.player.weapon
  S.overcharge = pickup.value
  w.damage, w.fireRate = S.baseDamage * 2, S.baseRate * 0.6
  return true
end)

-- world3dDraw runs inside the 3D camera: draw3d.* here, not draw.*.
hooks.on("world3dDraw", function(world)
  if not siege(world) then return end
  if S.nextAt then
    draw3d.text(say("WAVE ", "OLEADA ") .. world.wave + 1, 0, 30, 0, 40, "#ffffff")
  end
  draw3d.text("JUMP", 60, 8, 60, 20, "#40ff80")
  draw3d.cubeWires(60, 1.5, 60, 20, 1, 20, "#40ff8080")
end)

-- world3dDrawHud draws in screen pixels over the 3D view: draw.* works here.
hooks.on("world3dDrawHud", function(world, w, h)
  if not siege(world) then return end
  local p, wp = world.player, world.player.weapon
  -- HP bar, bottom left
  local frac = math.clamp(p.health / p.maxHealth, 0, 1)
  draw.rect(22, h - 50, 264, 26, "#000000b0")
  draw.rect(24, h - 48, 260 * frac, 22, frac > 0.35 and "#40e070" or "#ff4040")
  draw.text(say("HP ", "VIDA ") .. math.ceil(p.health), 32, h - 45, 16, "#ffffff")
  if S.overcharge > 0 then
    draw.text(string.format("OVERCHARGE %.1f", S.overcharge), 24, h - 74, 16, "#ff40ff")
  end
  -- Ammo, bottom right
  local ammo = wp.reloadTimer > 0 and say("RELOADING", "RECARGANDO") or (wp.ammo .. " / " .. wp.maxAmmo)
  draw.text(ammo, w - draw.textWidth(ammo, 26) - 28, h - 48, 26, wp.ammo > 0 and "#ffd060" or "#ff4040")
  -- Wave, score and enemies left, top centre
  local line = say("WAVE ", "OLEADA ") .. math.max(world.wave, 1) .. "/" .. TOTAL_WAVES
               .. "   " .. say("SCORE ", "PUNTOS ") .. world.score
               .. "   " .. #world3d.entities() .. say(" left", " restantes")
  draw.text(line, (w - draw.textWidth(line, 22)) / 2, 18, 22, "#ffffff")
end)

-- ================================================= the Orbital Commander ====
-- Not a mode of ours: these hooks touch only the game's own boss-7 world.

local message, messageUntil = "", 0

local function bossFight(world) return world.bossEnabled and world.bossId == 7 end

-- A drone that circles the player and fires now and then
local function spawnDrone(angle)
  local p = world3d.player
  world3d.spawn{tag = "drone", x = p.pos.x + math.cos(angle) * 60, y = p.pos.y + 15, z = p.pos.z + math.sin(angle) * 60,
                hp = 25, radius = 3, shape = "sphere", color = "#40d0ff", ai = "orbit", orbitRadius = 55, speed = 30,
                fireInterval = 3, projectileSpeed = 80, projectileDamage = 5, range = 250, scoreValue = 50}
end

hooks.on("world3dStart", function(world, resumed)
  if not bossFight(world) then return end
  for i = 0, 3 do spawnDrone(i / 4 * math.pi * 2) end
  message, messageUntil = "4 DRONES INBOUND", world.timeElapsed + 3
end)

-- Every boss phase change: a message, and two more drones from phase 2 on
hooks.on("world3dBossPhase", function(phase)
  local world = world3d.world
  if not bossFight(world) then return end
  message, messageUntil = "PHASE " .. phase, world.timeElapsed + 3
  if phase >= 2 then
    spawnDrone(math.random() * math.pi * 2)
    spawnDrone(math.random() * math.pi * 2)
  end
end)

-- The hit filter: (damage, target, projectile) -> the damage that lands.
-- target is "boss", "satellite", or an entity (one of our drones).
hooks.on("world3dHit", function(damage, target, projectile)
  if bossFight(world3d.world) and target == "satellite" then return damage * 1.5 end
end)

-- Killing a drone heals the player a little
hooks.on("world3dEntityDeath", function(e)
  if e.tag == "drone" and bossFight(world3d.world) then world3d.healPlayer(5) end
end)

hooks.on("world3dDrawHud", function(world, w, h)
  if bossFight(world) and world.timeElapsed < messageUntil then
    draw.text(message, (w - draw.textWidth(message, 36)) / 2, h * 0.25, 36, "#7de2ff")
  end
end)
