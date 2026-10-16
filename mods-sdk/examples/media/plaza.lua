-- Billboard Plaza: a 3D game mode (MODS.EXE > Game Modes) that shows every
-- way a picture gets into a 3D world:
--
--   draw3d.texture    a flat picture fixed in the world: the big screen (a
--                     video with sound), a poster (PNG), a neon sign (GIF), a
--                     turning video panel and a decal on the floor.
--   draw3d.billboard  a sprite that turns to face you: glowing orbs (a PNG
--                     with soft see-through edges) and a hovering video.
--   override.texture  an entity whose body is a picture: the drones (a GIF).
--
-- Shoot the big screen to pause or play it. Its sound gets louder as you
-- walk up to it.

local function say(en, es) return lang.current() == "es" and es or en end

local MODE = register.gamemode{
  id = "plaza",
  name = {en = "Billboard Plaza", es = "Plaza de Carteles"},
  description = {
    en = "First person. Walk around a plaza of video screens, posters and signs. Shoot the big screen to pause or play it.",
    es = "En primera persona. Recorre una plaza de pantallas de video, carteles y letreros. Dispara a la pantalla grande para pausarla o reanudarla.",
  },
  base = "3d",
  resumable = false,       -- quitting ends the visit instead of saving it
  restorePoints = false,   -- and there are no restore points (no CONTINUE)
  onStart = function(game, resumed)
    hud.hide("player")     -- no HP or ammo box: nothing here can hurt you
  end,
}

-- A video goes wherever a texture goes. One file is one playback: everything
-- that draws plasma.mpg shows the same picture.
local card = assets.video("test_card.mpg")   -- 8 s: a counter, a beep and a flash each second
local plasma = assets.video("plasma.mpg")    -- a silent 4 s loop
local orb = assets.texture("orb.png")
local decal = assets.texture("decal.png")

-- Every entity tagged "plaza_drone" is drawn as this GIF, facing the camera.
override.texture("entity3d:plaza_drone", "drone.gif", {scale = 1.6})

-- The screens around the plaza, each on a box (a platform) with a post. yaw
-- turns a picture like a model: 0 faces +z, 90 faces +x.
local SCREENS = {
  {tex = card, x = 0, y = 30, z = -110, w = 64, h = 36, yaw = 0},
  {tex = assets.texture("poster.png"), x = -90, y = 20, z = -30, w = 20, h = 30, yaw = 90},
  {tex = assets.texture("online.gif"), x = 90, y = 18, z = -30, w = 40, h = 20, yaw = -90},  -- a GIF animates by itself
}
local BIG = SCREENS[1]
local PANEL = {x = -50, y = 16, z = -75}   -- the turning plasma panel

local S = {}   -- per world, replaced in world3dStart

local function active(world) return world.modeKey == MODE end

local function buildPlaza(world)
  world3d.arena{theme = "empty", radius = 160, sky = "#070a14", floor = "#10141f", wall = "#2a3350"}
  world3d.platform{x = 0, y = -1, z = 0, w = 320, h = 2, d = 320, color = "#161c2a"}   -- the ground, its top at 0
  for _, s in ipairs(SCREENS) do
    -- The box sits just behind the picture: the small gap keeps the two
    -- from flickering through each other.
    local fx, fz = math.sin(math.rad(s.yaw)), math.cos(math.rad(s.yaw))
    local x, z = s.x - fx * 1.25, s.z - fz * 1.25
    local facesZ = math.abs(fz) > 0.5   -- then the screen spans x
    s.box = world3d.platform{x = x, y = s.y, z = z, w = facesZ and s.w + 3 or 2, h = s.h + 3,
                             d = facesZ and 2 or s.w + 3, color = "#1c2433"}
    local bottom = s.y - (s.h + 3) / 2
    world3d.platform{x = x, y = bottom / 2, z = z, w = 2, h = bottom, d = 2, color = "#2c3548"}
  end
  world3d.platform{x = PANEL.x, y = 4, z = PANEL.z, w = 2, h = 8, d = 2, color = "#2c3548"}
  -- Start on the plaza, looking at the big screen. The camera's yaw is not a
  -- picture's: 0 looks along +x, -90 along -z.
  world.spawnPos = {x = 0, y = 1, z = 70}
  world.player.pos = {x = 0, y = 1, z = 70}
  world.camera.yaw = -90
end

local function spawnDrone()
  local a = math.random() * math.pi * 2
  local r = 20 + math.random() * 45
  world3d.spawn{tag = "plaza_drone", x = math.cos(a) * r, y = 10 + math.random() * 8, z = -30 + math.sin(a) * r,
                hp = 20, radius = 3, ai = "wander", speed = 14, gravity = false, contactDamage = 0}
end

-- ------------------------------------------------------------------ hooks ----
hooks.on("world3dStart", function(world, resumed)
  if not active(world) then return end
  S = {nextDrone = 3}
  buildPlaza(world)
  local wp = world.player.weapon
  wp.infiniteAmmo = true
  wp.fireRate = 0.2
  wp.projectileColor = "#9fe8ff"
  for _ = 1, 4 do spawnDrone() end
  card:stop()      -- each visit starts the clips from their first picture
  plasma:stop()
end)

hooks.on("world3dUpdate", function(world, dt)
  if not active(world) then return end
  -- The big screen's sound fades with distance (a video's volume goes 0 to 4).
  local p = world.player.pos
  local d = math.sqrt((p.x - BIG.x) ^ 2 + (p.z - BIG.z) ^ 2)
  card.volume = math.clamp(1 - (d - 30) / 160, 0.05, 1)
  -- Is the crosshair on the big screen? raycast stops at the first thing in
  -- the way (a drone, a box) and names the platform it hit.
  local hit = world3d.raycast(world3d.aim())
  S.aimed = hit.kind == "platform" and hit.platform == BIG.box
  -- Shot drones come back, one every 3 s.
  if world.timeElapsed >= S.nextDrone and #world3d.entities("plaza_drone") < 4 then
    spawnDrone()
    S.nextDrone = world.timeElapsed + 3
  end
end)

-- A shot at the big screen goes to the screen: returning true replaces it.
hooks.on("world3dShoot", function(world)
  if active(world) and S.aimed then
    S.cardOff = not S.cardOff
    return true
  end
end)

-- ---------------------------------------------------------------- drawing ----
hooks.on("world3dDraw", function(world)
  if not active(world) then return end
  local t = world.timeElapsed

  -- A video plays while something draws it, and a paused world is still
  -- drawn under its pause screen: so hold the clips while it is paused.
  if world.paused or S.cardOff then card:pause() else card:play() end
  if world.paused then plasma:pause() else plasma:play() end

  for _, s in ipairs(SCREENS) do
    draw3d.texture(s.tex, s.x, s.y, s.z, {w = s.w, h = s.h, yaw = s.yaw})
  end
  -- A panel that turns a little every frame (both sides of a picture show
  -- it). Given only h, its width follows the video's shape.
  draw3d.texture(plasma, PANEL.x, PANEL.y, PANEL.z, {h = 16, yaw = t * 25})
  -- The same video as a billboard, which turns to face you.
  draw3d.billboard(plasma, PANEL.x, PANEL.y + 20 + math.sin(t * 1.5) * 1.5, PANEL.z, 10)
  -- A decal: pitch -90 lays it face up, its top toward -z (the arrow points at the big screen).
  draw3d.texture(decal, 0, 0.1, 48, {w = 24, pitch = -90})

  -- Half see-through sprites go last, farthest first: a soft edge hides
  -- whatever is drawn after it, behind it.
  local cam = world.camera.position
  local orbs = {}
  for i = 1, 10 do
    local a = i / 10 * math.pi * 2 + t * 0.3
    local o = {x = math.cos(a) * 35, y = 12 + math.sin(t * 2 + i) * 2, z = -30 + math.sin(a) * 35}
    o.d = (o.x - cam.x) ^ 2 + (o.y - cam.y) ^ 2 + (o.z - cam.z) ^ 2
    orbs[i] = o
  end
  table.sort(orbs, function(a, b) return a.d > b.d end)
  for _, o in ipairs(orbs) do draw3d.billboard(orb, o.x, o.y, o.z, 6) end

  -- Labels at a point in the world, drawn over the scene.
  draw3d.text("draw3d.texture", BIG.x, BIG.y + BIG.h / 2 + 5, BIG.z, 20, "#9fe8ff")
  draw3d.text("draw3d.billboard", PANEL.x, PANEL.y + 32, PANEL.z, 14, "#9fe8ff")
end)

local function clock(t)
  t = math.floor(t)
  return string.format("%d:%02d", t // 60, t % 60)
end

hooks.on("world3dDrawHud", function(world, w, h)
  if not active(world) then return end
  local lines = {
    say("BILLBOARD PLAZA", "PLAZA DE CARTELES"),
    "test_card.mpg  " .. clock(card.time) .. " / " .. clock(card.duration) .. "  "
      .. (card.paused and say("paused", "en pausa") or say("playing", "reproduciendo"))
      .. "  " .. math.round(card.volume * 100) .. "%",
    "draw3d.texture: test_card.mpg, poster.png, online.gif, plasma.mpg, decal.png",
    "draw3d.billboard: orb.png, plasma.mpg",
    "override.texture: drone.gif x" .. #world3d.entities("plaza_drone"),
  }
  local width = 0
  for _, line in ipairs(lines) do width = math.max(width, draw.textWidth(line, 14)) end
  draw.rect(6, 6, width + 20, #lines * 20 + 12, "#000000a8")
  for i, line in ipairs(lines) do
    draw.text(line, 16, 14 + (i - 1) * 20, 14, i == 1 and "#ffd060" or "#e0e8f0")
  end
  -- What a click would do, under the crosshair.
  if S.aimed then
    local text = say("[CLICK] ", "[CLIC] ") .. (card.paused and say("play", "reproducir") or say("pause", "pausar"))
    draw.text(text, (w - draw.textWidth(text, 18)) / 2, h / 2 + 28, 18, "#ffd060")
  end
end)
