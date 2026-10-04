-- Cube Siege: a whole game mode that lives in a 3D world.
--
-- base = "3d" launches straight into an EMPTY first-person world (no 2D arena,
-- no boss). Everything in it is built by this script: the arena, the waves,
-- the pickups, the weapon, the HUD. The world3d* hooks below run for every 3D
-- world, so each one first checks that this mode is the one being played.
--
-- Controls are the game's own 3D ones: WASD, Space (double jump), Shift,
-- mouse, left click = shoot, R = reload, Esc = pause. This mod adds right
-- click = a shockwave.

local MODE = register.gamemode{
  id = "cube_siege",
  name = {en = "Cube Siege", es = "Asedio de Cubos"},
  description = {
    en = "First person. Survive six waves of cubes, drones and turrets with a shotgun. Right click fires a shockwave.",
    es = "En primera persona. Sobrevive a seis oleadas de cubos, drones y torretas con una escopeta. El clic derecho lanza una onda de choque.",
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

-- Per-world state lives in one table that world3dStart replaces. Plain Lua
-- values are fine here (this is not saved; run.data below is).
local S = {blasts = {}, altCooldown = 0, overcharge = 0}

local function active(world)
  return world.modeKey == MODE
end

local function say(en, es)
  return lang.current() == "es" and es or en
end

-- ------------------------------------------------------------------ arena ----

local function buildArena()
  -- An "empty" world already has a solid floor (at y = -9.5). We lay our own
  -- big platform on top as a deliberate arena ground: it gives the fight a
  -- coloured floor at y = 0, and the drop below its edge is the floor, not the void.
  world3d.arena{
    theme = "empty",             -- a bare arena; we add our own platforms
    radius = 320,                -- also sets the walls: the player stays inside 0.9 x radius
    sky = "#0b1020", floor = "#1c2333", wall = "#39435c",
  }
  world3d.platform{x = 0, y = -1, z = 0, w = 640, h = 2, d = 640, color = "#242c40"}
  -- The player starts on the world's solid floor, beneath that platform: stand
  -- them on it instead (and bring them back there after a fall).
  world3d.world.spawnPos = {x = 0, y = 1, z = 0}
  world3d.player.pos = {x = 0, y = 1, z = 0}

  -- Four raised platforms (w, h, d are FULL sizes)
  for i = 0, 3 do
    local a = i / 4 * math.pi * 2 + math.pi / 4
    world3d.platform{x = math.cos(a) * 130, y = 14, z = math.sin(a) * 130,
                     w = 40, h = 3, d = 40, color = "#3b5b8c"}
  end
  -- One that slides back and forth
  world3d.platform{x = 0, y = 34, z = -120, w = 34, h = 3, d = 34, color = "#8c5b3b",
                   moving = true, moveSpeed = 0.5}
  -- A jump pad: walk onto it and it throws you into the air
  world3d.platform{x = 60, y = 0.5, z = 60, w = 20, h = 1, d = 20, color = "#40ff80",
                   jumpPad = true, jumpForce = 900}
end

local function tuneWeapon(world)
  local p = world.player
  p.maxHealth = 100
  p.health = 100
  p.speed = 80
  p.hitInvuln = 0.4              -- a short grace period after each hit

  -- A shotgun: many weak pellets in a cone, slow to fire, with a reload
  local w = p.weapon
  w.pellets = 8
  w.spread = 4                   -- degrees, each pellet strays up to this far
  w.damage = 12                  -- per pellet
  w.fireRate = 0.7               -- seconds between shots
  w.projectileSpeed = 520
  w.projectileRadius = 1.1
  w.projectileColor = "#ffd060"
  w.maxAmmo = 24
  w.ammo = 24
  w.reloadTime = 1.2
  S.baseDamage, S.baseRate = w.damage, w.fireRate
end

-- ------------------------------------------------------------------ waves ----
-- Each wave is a list of things to spawn. Nothing appears at once: first a
-- red marker shows where (see world3dDraw), then S.plan is spawned.

local function ringPoint(radius)
  local a = math.random() * math.pi * 2
  return math.cos(a) * radius, math.sin(a) * radius
end

local function planWave(n)
  local plan = {}
  local function add(kind)
    local x, z = ringPoint(150 + math.random() * 90)
    plan[#plan + 1] = {kind = kind, x = x, z = z}
  end
  for _ = 1, 3 + n * 2 do add("chaser") end
  if n >= 2 then for _ = 1, n - 1 do add("orbiter") end end
  if n >= 3 then for _ = 1, 1 + (n - 3) // 2 do add("turret") end end
  add("brute")                  -- one tougher enemy every wave
  return plan
end

-- Entity fields: hp, radius, color, shape, size, speed, ai, contactDamage,
-- scoreValue, gravity, ... The built-in AI moves them; we only describe them.
local function spawnOne(item, n)
  local kind = item.kind
  if kind == "chaser" then
    world3d.spawn{tag = "chaser", x = item.x, y = 4, z = item.z, hp = 30, radius = 4,
      shape = "cube", size = 7, color = "#e04848", ai = "chase", speed = 22 + n * 2,
      contactDamage = 8, scoreValue = 10, gravity = true}
  elseif kind == "orbiter" then
    -- flies (no gravity), circles the player and shoots
    world3d.spawn{tag = "orbiter", x = item.x, y = 28, z = item.z, hp = 20, radius = 3.5,
      shape = "sphere", color = "#40d0ff", ai = "orbit", orbitRadius = 70, speed = 34,
      fireInterval = 2.2, projectileSpeed = 90, projectileDamage = 6, range = 220,
      scoreValue = 20, gravity = false}
  elseif kind == "turret" then
    -- stands still, shoots, and blocks the way (solid)
    world3d.spawn{tag = "turret", x = item.x, y = 5, z = item.z, hp = 60, radius = 5,
      shape = "cylinder", size = 10, color = "#c080ff", ai = "turret",
      fireInterval = 1.6, projectileSpeed = 110, projectileDamage = 8, range = 260,
      scoreValue = 30, gravity = true, solid = true}
  else -- brute
    world3d.spawn{tag = "brute", x = item.x, y = 9, z = item.z, hp = 150 + n * 40, radius = 8,
      shape = "cube", size = 15, color = "#ff8a30", ai = "chase", speed = 16,
      contactDamage = 20, scoreValue = 100, gravity = true}
  end
end

local function persist(world)
  -- run.data is saved with the run. If the player quits and continues, the
  -- world is rebuilt from scratch, so we keep just enough to pick up again.
  run.data.wave = world.wave
  run.data.score = world.score
  run.data.hp = world.player.health
end

local function beginWave(world)
  world.wave = world.wave + 1     -- world.wave and world.score are ours to use
  S.plan = planWave(world.wave)
  S.spawnAt = world.timeElapsed + 2   -- the markers show for 2 seconds
  persist(world)
end

-- ----------------------------------------------------------------- hooks ----

hooks.on("world3dStart", function(world, resumed)
  if not active(world) then return end
  S = {blasts = {}, altCooldown = 0, overcharge = 0}
  buildArena()
  tuneWeapon(world)
  if resumed and run.data.wave then
    -- Continue: start again from the wave that was in progress, with the
    -- score and HP the player had when it began.
    world.wave = math.floor(run.data.wave) - 1
    world.score = math.floor(run.data.score or 0)
    world.player.health = math.max(30, run.data.hp or 100)
  end
  S.nextAt = world.timeElapsed + 2
end)

hooks.on("world3dUpdate", function(world, dt)
  if not active(world) or S.done then return end
  local p = world.player

  -- Overcharge pickup: double damage for a few seconds
  if S.overcharge > 0 then
    S.overcharge = S.overcharge - dt
    if S.overcharge <= 0 then
      p.weapon.damage, p.weapon.fireRate = S.baseDamage, S.baseRate
    end
  end

  -- Alt-fire: right click, costs 6 shells, 2.5 s cooldown. It hits wherever
  -- the crosshair points and hurts everything near that spot.
  S.altCooldown = S.altCooldown - dt
  if input.mousePressed("right") and S.altCooldown <= 0 and p.weapon.ammo >= 6 then
    S.altCooldown = 2.5
    p.weapon.ammo = p.weapon.ammo - 6
    local ox, oy, oz, dx, dy, dz = world3d.aim()
    local hit = world3d.raycast(ox, oy, oz, dx, dy, dz, 400)
    for _, e in ipairs(world3d.entities()) do
      if e:distanceTo(hit.x, hit.y, hit.z) < 35 then
        local dealt = e:damage(70)
        world3d.damageNumber(e.x, e.y + 6, e.z, dealt, "#ff9020")
      end
    end
    S.blasts[#S.blasts + 1] = {x = hit.x, y = hit.y, z = hit.z, t = world.timeElapsed}
    world3d.shake(0.4)
  end

  -- The wave director: warm-up -> spawn -> fight -> pause -> next wave
  if S.plan then
    if world.timeElapsed >= S.spawnAt then
      for _, item in ipairs(S.plan) do spawnOne(item, world.wave) end
      S.plan = nil
    end
  elseif S.nextAt then
    if world.timeElapsed >= S.nextAt then
      S.nextAt = nil
      beginWave(world)
    end
  elseif world.wave > 0 and #world3d.entities() == 0 then
    if world.wave >= TOTAL_WAVES then
      S.done = true
      world3d.finish(true)         -- true = won (the victory screen)
    else
      S.nextAt = world.timeElapsed + 3
    end
  end
end)

-- A normal shot: hooks can also just watch. Returning nothing lets the
-- built-in shotgun fire; returning true would cancel it.
hooks.on("world3dShoot", function(world)
  if active(world) then world3d.shake(0.08) end
end)

-- Drops. The death hook can still read the dead entity (x, y, z, tag...).
hooks.on("world3dEntityDeath", function(e)
  local world = world3d.world
  if not active(world) then return end
  local y = math.max(e.y, 3)
  local r = math.random()
  if e.tag == "brute" then
    world3d.pickup{x = e.x, y = y, z = e.z, kind = "health", value = 40}
    world3d.pickup{x = e.x + 6, y = y, z = e.z, kind = "overcharge", value = 8,
                   color = "#ff40ff", radius = 5}
  elseif r < 0.25 then
    world3d.pickup{x = e.x, y = y, z = e.z, kind = "health", value = 20}
  elseif r < 0.55 then
    world3d.pickup{x = e.x, y = y, z = e.z, kind = "ammo", value = 8}
  elseif r < 0.60 then
    world3d.pickup{x = e.x, y = y, z = e.z, kind = "overcharge", value = 8,
                   color = "#ff40ff", radius = 5}
  end
end)

-- Pickups: health and ammo have built-in effects. "overcharge" is ours, so we
-- take it ourselves: returning true means "taken, skip the built-in effect".
hooks.on("world3dPickup", function(pickup)
  if not active(world3d.world) or pickup.kind ~= "overcharge" then return end
  local w = world3d.player.weapon
  S.overcharge = pickup.value
  w.damage, w.fireRate = S.baseDamage * 2, S.baseRate * 0.6
  world3d.damageNumber(pickup.x, pickup.y + 4, pickup.z, 2, "#ff40ff")   -- shows "2"
  return true
end)

-- ------------------------------------------------------------- 3D drawing ----
-- world3dDraw runs inside the 3D camera: use draw3d.* here (not draw.*).

local function ring(cx, cy, cz, r, color, segments)
  segments = segments or 48
  local px, pz = cx + r, cz
  for i = 1, segments do
    local a = i / segments * math.pi * 2
    local x, z = cx + math.cos(a) * r, cz + math.sin(a) * r
    draw3d.line(px, cy, pz, x, cy, z, color)
    px, pz = x, z
  end
end

hooks.on("world3dDraw", function(world)
  if not active(world) then return end
  local t = world.timeElapsed

  -- Warm-up: a wireframe marker where each enemy is about to appear
  if S.plan then
    for _, item in ipairs(S.plan) do
      local bob = math.sin(t * 6) * 1.5
      draw3d.cubeWires(item.x, 6 + bob, item.z, 9, 9, 9, "#ff4040")
      draw3d.line(item.x, 0, item.z, item.x, 40, item.z, "#ff404080")
    end
  end

  -- Between waves: rings that expand from the middle, and a label
  if S.plan or S.nextAt then
    ring(0, 1, 0, (t * 60) % 200, "#40ff80")
    ring(0, 1, 0, (t * 60 + 100) % 200, "#40ff8080")
    draw3d.text(say("WAVE ", "OLEADA ") .. (S.plan and world.wave or world.wave + 1), 0, 30, 0, 40, "#ffffff")
  end

  -- Shockwaves: a wire sphere that grows and fades
  for i = #S.blasts, 1, -1 do
    local b = S.blasts[i]
    local age = t - b.t
    if age > 0.5 then
      table.remove(S.blasts, i)
    else
      draw3d.sphereWires(b.x, b.y, b.z, 5 + age * 60, {255, 160, 40, math.floor(255 * (1 - age * 2))}, 8, 8)
    end
  end

  draw3d.text("JUMP", 60, 8, 60, 20, "#40ff80")
end)

-- --------------------------------------------------------------------- HUD ----
-- world3dDrawHud draws in screen pixels over the 3D view: draw.* works here.

hooks.on("world3dDrawHud", function(world, w, h)
  if not active(world) then return end
  local p = world.player

  -- HP bar, bottom left
  local bx, by, bw, bh = 24, h - 48, 260, 22
  draw.rect(bx - 2, by - 2, bw + 4, bh + 4, "#000000b0")
  local frac = math.clamp(p.health / p.maxHealth, 0, 1)
  draw.rect(bx, by, bw * frac, bh, frac > 0.35 and "#40e070" or "#ff4040")
  draw.text(say("HP ", "VIDA ") .. math.ceil(p.health), bx + 8, by + 3, 16, "#ffffff")

  -- Ammo, bottom right
  local wp = p.weapon
  local ammo = wp.reloadTimer > 0 and say("RELOADING", "RECARGANDO") or (wp.ammo .. " / " .. wp.maxAmmo)
  local aw = draw.textWidth(ammo, 26)
  draw.text(ammo, w - aw - 28, h - 48, 26, wp.ammo > 0 and "#ffd060" or "#ff4040")

  -- Score and wave, top centre
  local line = say("WAVE ", "OLEADA ") .. math.max(world.wave, 1) .. "/" .. TOTAL_WAVES
               .. "   " .. say("SCORE ", "PUNTOS ") .. world.score
  draw.text(line, (w - draw.textWidth(line, 22)) / 2, 18, 22, "#ffffff")
  local left = #world3d.entities()
  if left > 0 then
    local sub = left .. say(" left", " restantes")
    draw.text(sub, (w - draw.textWidth(sub, 14)) / 2, 46, 14, "#c0c8e0")
  end

  -- Overcharge timer and shockwave cooldown
  if S.overcharge > 0 then
    draw.text(string.format("OVERCHARGE %.1f", S.overcharge), bx, by - 26, 16, "#ff40ff")
  end
  local ready = S.altCooldown <= 0
  draw.text(ready and say("[RIGHT CLICK] SHOCKWAVE", "[CLIC DERECHO] ONDA") or
            string.format("SHOCKWAVE %.1f", S.altCooldown),
            w - 260, h - 76, 14, ready and "#ff9020" or "#808080")
end)

hooks.on("world3dEnd", function(world, result)
  if active(world) then
    mod.log("Cube Siege ended: " .. result .. ", score " .. world.score .. ", wave " .. world.wave)
  end
end)
