-- Orbital Tweaks: changing the game's own 3D boss fight.
--
-- Wave boss 7 (the Orbital Commander) is fought in a 3D world. This mod does
-- not add a game mode: it just uses the world3d* hooks, which run for every
-- 3D world, and checks world.bossEnabled to only touch that fight.

local message, messageUntil = "", 0

local function isBossFight(world)
  return world.bossEnabled and world.bossId == 7
end

-- A drone that circles the player and fires now and then
local function spawnDrone(angle)
  local p = world3d.player
  world3d.spawn{
    tag = "drone",
    x = p.pos.x + math.cos(angle) * 60, y = p.pos.y + 15, z = p.pos.z + math.sin(angle) * 60,
    hp = 25, radius = 3, shape = "sphere", color = "#40d0ff",
    ai = "orbit", orbitRadius = 55, speed = 30,
    fireInterval = 3, projectileSpeed = 80, projectileDamage = 5, range = 250,
    scoreValue = 50,
  }
end

hooks.on("world3dStart", function(world, resumed)
  if not isBossFight(world) then return end
  for i = 0, 3 do spawnDrone(i / 4 * math.pi * 2) end
  message, messageUntil = "4 DRONES INBOUND", world.timeElapsed + 3
end)

-- Every boss phase change: a message, and two more drones from phase 2 on
hooks.on("world3dBossPhase", function(phase)
  local world = world3d.world
  if not isBossFight(world) then return end
  message, messageUntil = "PHASE " .. phase, world.timeElapsed + 3
  if phase >= 2 then
    spawnDrone(math.random() * math.pi * 2)
    spawnDrone(math.random() * math.pi * 2)
  end
end)

-- The hit filter: (damage, target, projectile) -> the damage that lands.
-- target is "boss", "satellite", or one of our drones (an entity).
hooks.on("world3dHit", function(damage, target, projectile)
  if not isBossFight(world3d.world) then return end
  if target == "satellite" then return damage * 1.5 end
end)

-- Killing a drone heals the player a little
hooks.on("world3dEntityDeath", function(e)
  if e.tag == "drone" and isBossFight(world3d.world) then
    world3d.healPlayer(5)
  end
end)

hooks.on("world3dDrawHud", function(world, w, h)
  if isBossFight(world) and world.timeElapsed < messageUntil then
    draw.text(message, (w - draw.textWidth(message, 36)) / 2, h * 0.25, 36, "#7de2ff")
  end
end)
