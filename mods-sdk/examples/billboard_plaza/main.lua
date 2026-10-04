-- Billboard Plaza: videos and images on 3D billboards.
--
-- A 3D game mode (MODS.EXE > Game Modes) that is a walk-around test of every
-- way a picture gets into a 3D world:
--
--   draw3d.texture    a flat picture FIXED in the world, that does not turn
--                     to face you: the big screen (a video with sound), a
--                     poster (PNG), a neon sign (GIF), a turning column of
--                     video screens and a decal on the floor.
--   draw3d.billboard  a sprite that turns to FACE you: glowing orbs (a PNG
--                     with soft see-through edges) and a hovering video.
--   override.texture  an entity whose body is a picture: the drifting drones
--                     (a GIF with a see-through background).
--
-- Shoot a screen to pause or play it, the poster to switch its light, the
-- sign to freeze it. The big screen's sound gets louder as you walk up to it.
-- H folds the panel in the corner.

local MODE = register.gamemode{
  id = "plaza",
  name = {en = "Billboard Plaza", es = "Plaza de Carteles"},
  description = {
    en = "First person. Walk around a plaza of video screens, posters and signs. Shoot a screen to pause or play it.",
    es = "En primera persona. Recorre una plaza de pantallas de video, carteles y letreros. Dispara a una pantalla para pausarla o reanudarla.",
  },
  base = "3d",
  -- A showroom has nothing to come back to. resumable = false: quitting ends
  -- the visit instead of saving it, so the desktop never offers to resume it.
  resumable = false,
  -- And no restore points at all: no checkpoint is written, the crash screen
  -- offers no CONTINUE, and no restore-point glyphs are drawn anywhere. (A
  -- number would set the budget instead, and restoreGlyphs = false would keep
  -- continues but hide the meters.)
  restorePoints = false,
  onStart = function(game, resumed)
    hud.hide("player")   -- no HP or ammo box: nothing here can hurt you
  end,
}

local function say(en, es) return lang.current() == "es" and es or en end

-- ----------------------------------------------------------------- assets ----
-- A video goes wherever a texture goes. One file is one playback: everything
-- that draws plasma.mpg shows the same picture, and pausing it pauses them all.
local card = assets.video("test_card.mpg")   -- 8 s: a counter, a beep and a flash each second
local plasma = assets.video("plasma.mpg")    -- a silent 4 s loop
local poster = assets.texture("poster.png")
local decal = assets.texture("decal.png")
local orb = assets.texture("orb.png")
local neon = assets.texture("online.gif")    -- a GIF animates by itself

-- Every entity tagged "plaza_drone" is drawn as this GIF, turned to face the
-- camera. An override holds in every world, so the tag is our own.
override.texture("entity3d:plaza_drone", "drone.gif", {scale = 1.6})

-- ------------------------------------------------------------------ state ----
local S = {}   -- per world, replaced in world3dStart

local function active(world)
  return world.modeKey == MODE
end

-- yaw turns a picture about the vertical axis like a model: 0 faces +z, 90
-- faces +x. Its front then points along (sin, cos) and its right edge runs
-- along (cos, -sin).
local function facing(yaw)
  local r = math.rad(yaw)
  return math.sin(r), math.cos(r)
end

-- --------------------------------------------------------------- screens ----
-- The screens fixed around the plaza. They face its middle at whole quarter
-- turns, so the box behind each one can be a platform (platforms do not turn).
-- A missing w or h comes from the picture's own shape.
local SCREENS = {
  {id = "card", tex = card, x = 0, y = 30, z = -110, w = 64, h = 36, yaw = 0,
   name = {"TEST CARD", "CARTA DE AJUSTE"}, file = "test_card.mpg"},
  {id = "poster", tex = poster, x = -90, y = 20, z = -30, h = 30, yaw = 90,
   name = {"POSTER", "CARTEL"}, file = "poster.png"},
  {id = "neon", tex = neon, x = 90, y = 18, z = -30, w = 40, yaw = -90,
   name = {"NEON SIGN", "LETRERO"}, file = "online.gif"},
}

local COLUMN = {x = -50, y = 16, z = -75, half = 8}   -- four 16 x 16 faces of plasma.mpg
local BORDER, DEPTH, GAP = 1.5, 2, 0.25   -- the box around a screen, and the picture's lift off it

local function fitSize(s)
  local aspect = s.tex.width / s.tex.height
  if s.w and not s.h then s.h = s.w / aspect
  elseif s.h and not s.w then s.w = s.h * aspect end
end

local function buildScreen(s)
  fitSize(s)
  local fx, fz = facing(s.yaw)
  local alongX = math.abs(fz) > 0.5         -- facing z: the screen spans x
  local bw, bh = s.w + BORDER * 2, s.h + BORDER * 2
  -- The box sits behind the picture. The gap keeps the two from flickering
  -- through each other (depth precision drops with distance).
  local cx, cz = s.x - fx * (DEPTH / 2 + GAP), s.z - fz * (DEPTH / 2 + GAP)
  world3d.platform{x = cx, y = s.y, z = cz, w = alongX and bw or DEPTH, h = bh,
                   d = alongX and DEPTH or bw, color = "#1c2433"}
  local bottom = s.y - bh / 2
  for side = -1, 1, 2 do                    -- two posts down to the ground
    local off = side * s.w * 0.3
    world3d.platform{x = cx + (alongX and off or 0), y = bottom / 2, z = cz + (alongX and 0 or off),
                     w = 2, h = bottom, d = 2, color = "#2c3548"}
  end
end

local function buildPlaza(world)
  world3d.arena{theme = "empty", radius = 160, sky = "#070a14", floor = "#10141f", wall = "#2a3350"}
  world3d.platform{x = 0, y = -1, z = 0, w = 320, h = 2, d = 320, color = "#161c2a"}
  for _, s in ipairs(SCREENS) do buildScreen(s) end
  world3d.platform{x = COLUMN.x, y = (COLUMN.y - COLUMN.half) / 2, z = COLUMN.z,
                   w = 12, h = COLUMN.y - COLUMN.half, d = 12, color = "#2c3548"}
  -- Start on the plaza, looking at the big screen. The camera's yaw is not a
  -- model's: 0 looks along +x, -90 along -z.
  world.spawnPos = {x = 0, y = 1, z = 70}
  world.player.pos = {x = 0, y = 1, z = 70}
  world.camera.yaw = -90
end

-- Everything the crosshair can pick: the fixed screens and the column's
-- faces (which turn, so they are rebuilt every frame).
local function targets(world)
  local list = {}
  for _, s in ipairs(SCREENS) do list[#list + 1] = s end
  local spin = world.timeElapsed * 25
  for i = 0, 3 do
    local yaw = spin + i * 90
    local fx, fz = facing(yaw)
    list[#list + 1] = {id = "column", tex = plasma, yaw = yaw, w = COLUMN.half * 2, h = COLUMN.half * 2,
                       x = COLUMN.x + fx * COLUMN.half, y = COLUMN.y, z = COLUMN.z + fz * COLUMN.half}
  end
  return list
end

-- The screen under the crosshair: the aim ray against each picture's plane,
-- then world3d.raycast to check nothing solid (a box, a drone) is in front.
local function aimedScreen(world)
  local ox, oy, oz, dx, dy, dz = world3d.aim()
  local best, bestT = nil, math.huge
  for _, s in ipairs(targets(world)) do
    local fx, fz = facing(s.yaw)
    local denom = dx * fx + dz * fz
    if math.abs(denom) > 1e-4 then
      local t = ((s.x - ox) * fx + (s.z - oz) * fz) / denom
      if t > 0 and t < bestT then
        local px, py, pz = ox + dx * t, oy + dy * t, oz + dz * t
        local u = (px - s.x) * fz - (pz - s.z) * fx   -- along its right edge
        if math.abs(u) <= s.w / 2 and math.abs(py - s.y) <= s.h / 2 then
          best, bestT = s, t
        end
      end
    end
  end
  if best then
    local hit = world3d.raycast(ox, oy, oz, dx, dy, dz, bestT + 1)
    if hit.kind ~= "none" and hit.dist < bestT - 0.5 then return nil end
  end
  return best
end

-- What shooting a screen does, and how the HUD names its state.
local function toggle(world, s)
  if s.tex == card or s.tex == plasma then
    local clip = s.tex
    if clip.paused or clip.ended then clip:play() else clip:pause() end
  elseif s.id == "poster" then
    S.posterDim = not S.posterDim
  elseif s.id == "neon" then
    -- the sign runs on the world's clock (see world3dDraw): freezing it keeps
    -- the moment it was shot
    S.neonFrozenAt = not S.neonFrozenAt and world.timeElapsed or nil
  end
end

local function clipState(clip)
  if clip.ended then return say("ended", "terminado") end
  if clip.paused then return say("paused", "en pausa") end
  return say("playing", "reproduciendo")
end

local function clock(t)
  t = math.max(0, math.floor(t))
  return string.format("%d:%02d", t // 60, t % 60)
end

-- ---------------------------------------------------------------- drones ----
local function spawnDrone()
  local a = math.random() * math.pi * 2
  local r = 20 + math.random() * 45
  world3d.spawn{tag = "plaza_drone", x = math.cos(a) * r, y = 10 + math.random() * 8,
                z = -30 + math.sin(a) * r, hp = 20, radius = 3, ai = "wander", speed = 14,
                gravity = false, contactDamage = 0, scoreValue = 1}
end

-- ----------------------------------------------------------------- hooks ----
hooks.on("world3dStart", function(world, resumed)
  if not active(world) then return end
  S = {pops = {}, respawns = {}, resume = {}}
  buildPlaza(world)
  local p = world.player
  p.weapon.infiniteAmmo = true
  p.weapon.fireRate = 0.2
  p.weapon.damage = 10
  p.weapon.projectileSpeed = 420
  p.weapon.projectileColor = "#9fe8ff"
  for _ = 1, 4 do spawnDrone() end
  card:stop()      -- each visit starts the clips from their first picture
  plasma:stop()
  card:play()
  plasma:play()
end)

hooks.on("world3dUpdate", function(world, dt)
  if not active(world) then return end
  -- The big screen's sound fades with distance (video volume goes 0 to 4).
  local p = world.player.pos
  local s = SCREENS[1]
  local d = math.sqrt((p.x - s.x) ^ 2 + (p.z - s.z) ^ 2)
  card.volume = math.clamp(1 - (d - 30) / 160, 0.05, 1)

  S.aimed = aimedScreen(world)
  if input.pressed("h") then S.hudFolded = not S.hudFolded end

  for i = #S.respawns, 1, -1 do
    if world.timeElapsed >= S.respawns[i] then
      table.remove(S.respawns, i)
      spawnDrone()
    end
  end
end)

-- A click on a screen goes to the screen: returning true replaces the shot.
hooks.on("world3dShoot", function(world)
  if not active(world) then return end
  local s = aimedScreen(world)
  if s then
    toggle(world, s)
    return true
  end
end)

hooks.on("world3dEntityDeath", function(e)
  if not active(world3d.world) or e.tag ~= "plaza_drone" then return end
  local t = world3d.world.timeElapsed
  S.pops[#S.pops + 1] = {x = e.x, y = e.y, z = e.z, t = t}
  S.respawns[#S.respawns + 1] = t + 3
end)

-- --------------------------------------------------------------- drawing ----
-- A video plays while something draws it, and a paused world is still drawn
-- (under the pause screen), so hold the clips while the world is paused and
-- let go of the ones that were playing on resume.
local CLIPS = {card, plasma}
local function holdForPause(world)
  if world.paused == S.held then return end
  S.held = world.paused
  for i, clip in ipairs(CLIPS) do
    if world.paused then
      S.resume[i] = not clip.paused and not clip.ended
      clip:pause()
    elseif S.resume[i] then
      clip:play()
    end
  end
end

local function outline(s, color)
  -- the four edges of a picture, a little proud of it
  local fx, fz = facing(s.yaw)
  local rx, rz = fz * (s.w / 2 + 0.6), -fx * (s.w / 2 + 0.6)
  local ox, oz = s.x + fx * 0.3, s.z + fz * 0.3
  local top, bottom = s.y + s.h / 2 + 0.6, s.y - s.h / 2 - 0.6
  draw3d.line(ox - rx, top, oz - rz, ox + rx, top, oz + rz, color)
  draw3d.line(ox - rx, bottom, oz - rz, ox + rx, bottom, oz + rz, color)
  draw3d.line(ox - rx, top, oz - rz, ox - rx, bottom, oz - rz, color)
  draw3d.line(ox + rx, top, oz + rz, ox + rx, bottom, oz + rz, color)
end

hooks.on("world3dDraw", function(world)
  if not active(world) then return end
  holdForPause(world)
  local t = world.timeElapsed

  -- Fixed pictures first (they are solid); w and h are given, so no stretching.
  for _, s in ipairs(SCREENS) do
    local opts = {w = s.w, h = s.h, yaw = s.yaw}
    if s.id == "poster" and S.posterDim then opts.tint = "#505060" end
    -- time = seconds into the GIF: on the world's clock it stops while paused
    if s.id == "neon" then opts.time = S.neonFrozenAt or t end
    draw3d.texture(s.tex, s.x, s.y, s.z, opts)
  end

  -- The column: four faces of one video, turned a little more every frame.
  for _, f in ipairs(targets(world)) do
    if f.id == "column" then draw3d.texture(f.tex, f.x, f.y, f.z, {w = f.w, h = f.h, yaw = f.yaw}) end
  end
  local capR = COLUMN.half * 1.45
  draw3d.cylinder(COLUMN.x, COLUMN.y + COLUMN.half + 0.75, COLUMN.z, capR, 1.5, "#2c3548", 24)
  draw3d.cylinder(COLUMN.x, COLUMN.y - COLUMN.half - 0.75, COLUMN.z, capR, 1.5, "#2c3548", 24)

  -- A decal: pitch -90 lays the picture face up, its top toward -z, so the
  -- arrow points at the big screen.
  draw3d.texture(decal, 0, 0.1, 48, {w = 24, pitch = -90})

  -- A video as a billboard: it turns to face you, 10 units tall.
  draw3d.billboard(plasma, COLUMN.x, COLUMN.y + COLUMN.half + 12 + math.sin(t * 1.5) * 1.5, COLUMN.z, 10)

  if S.aimed then outline(S.aimed, "#ffd060") end

  for i = #S.pops, 1, -1 do                 -- a drone popping
    local pop = S.pops[i]
    local age = t - pop.t
    if age > 0.4 then table.remove(S.pops, i)
    else draw3d.sphereWires(pop.x, pop.y, pop.z, 2 + age * 30, {120, 200, 255, math.floor(255 * (1 - age / 0.4))}) end
  end

  -- See-through sprites go last, farthest first. A sprite also fills the depth
  -- buffer where it is see-through, so anything drawn after it, behind it,
  -- would be cut off in that square.
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

  -- Labels are drawn over the scene, at a point in the world.
  draw3d.text("draw3d.texture", SCREENS[1].x, SCREENS[1].y + SCREENS[1].h / 2 + 5, SCREENS[1].z, 20, "#9fe8ff")
  draw3d.text("draw3d.billboard", COLUMN.x, COLUMN.y + COLUMN.half + 24, COLUMN.z, 14, "#9fe8ff")
end)

-- -------------------------------------------------------------------- HUD ----
hooks.on("world3dDrawHud", function(world, w, h)
  if not active(world) then return end
  -- The panel is laid out first and drawn after, so its background fits the
  -- longest line in either language.
  local lines = {}
  local function head(api, what)
    if not S.hudFolded then lines[#lines + 1] = {api, what, head = true} end
  end
  local function row(name, file, state)
    if not S.hudFolded then lines[#lines + 1] = {name, file, state} end
  end

  head("draw3d.texture", say("fixed in the world", "fija en el mundo"))
  row(say("TEST CARD", "CARTA DE AJUSTE"), "test_card.mpg",
      clock(card.time) .. "/" .. clock(card.duration) .. "  " .. clipState(card) ..
      string.format("  %d%%", math.floor(card.volume * 100 + 0.5)))
  row(say("COLUMN x4", "COLUMNA x4"), "plasma.mpg",
      clock(plasma.time) .. "/" .. clock(plasma.duration) .. "  " .. clipState(plasma))
  row(say("POSTER", "CARTEL"), "poster.png", S.posterDim and say("light off", "luz apagada") or say("light on", "luz encendida"))
  row(say("NEON SIGN", "LETRERO"), "online.gif",
      neon.frames .. say(" frames, ", " fotogramas, ") .. (S.neonFrozenAt and say("frozen", "congelado") or say("animating", "animado")))
  row(say("FLOOR DECAL", "CALCOMANÍA"), "decal.png")
  head("draw3d.billboard", say("turns to face you", "gira hacia ti"))
  row(say("ORBS x10", "ORBES x10"), "orb.png", say("see-through, farthest first", "translúcidos, del más lejano"))
  row(say("HOVERING", "FLOTANTE"), "plasma.mpg", say("same playback as the column", "misma reproducción que la columna"))
  head("override.texture", say("an entity's body", "el cuerpo de una entidad"))
  row(say("DRONES", "DRONES") .. " x" .. #world3d.entities("plaza_drone"), "drone.gif",
      say("shoot them", "dispárales"))

  local SIZE, LH, PAD = 14, 18, 10
  local title = say("BILLBOARD PLAZA", "PLAZA DE CARTELES")
  local hint = "[H] " .. (S.hudFolded and say("show", "mostrar") or say("hide", "ocultar"))
  local titleW = draw.textWidth(title, 20)
  local nameW, fileW, right = 0, 0, titleW + 14 + draw.textWidth(hint, SIZE)
  for _, l in ipairs(lines) do
    if l.head then
      right = math.max(right, draw.textWidth(l[1], SIZE) + 10 + draw.textWidth(l[2], SIZE))
    else
      nameW = math.max(nameW, draw.textWidth(l[1], SIZE))
      fileW = math.max(fileW, draw.textWidth(l[2], SIZE))
    end
  end
  local fileX, stateX = 12 + nameW + 16, 12 + nameW + 16 + fileW + 16
  for _, l in ipairs(lines) do
    if not l.head and l[3] then right = math.max(right, stateX + draw.textWidth(l[3], SIZE)) end
  end
  local x, y = 16, 16
  local heads = 0
  for _, l in ipairs(lines) do if l.head then heads = heads + 1 end end
  draw.rect(x - PAD, y - PAD, right + PAD * 2, 28 + #lines * LH + math.max(heads - 1, 0) * 4 + PAD * 2 - 4,
            "#000000a8")
  draw.text(title, x, y, 20, "#ffd060")
  draw.text(hint, x + titleW + 14, y + 4, SIZE, "#8090a8")
  y = y + 28
  for i, l in ipairs(lines) do
    if l.head then
      if i > 1 then y = y + 4 end
      draw.text(l[1], x, y, SIZE, "#9fe8ff")
      draw.text(l[2], x + draw.textWidth(l[1], SIZE) + 10, y, SIZE, "#8090a8")
    else
      draw.text(l[1], x + 12, y, SIZE, "#e0e8f0")
      draw.text(l[2], x + fileX, y, SIZE, "#a0b0c4")
      if l[3] then draw.text(l[3], x + stateX, y, SIZE, "#7dffb0") end
    end
    y = y + LH
  end

  -- What a click would do, under the crosshair.
  local s = S.aimed
  if s then
    local verb
    if s.tex == card or s.tex == plasma then
      verb = (s.tex.paused or s.tex.ended) and say("play", "reproducir") or say("pause", "pausar")
    elseif s.id == "poster" then
      verb = S.posterDim and say("light on", "encender la luz") or say("light off", "apagar la luz")
    else
      verb = S.neonFrozenAt and say("animate", "animar") or say("freeze", "congelar")
    end
    local text = say("[CLICK] ", "[CLIC] ") .. verb
    draw.text(text, (w - draw.textWidth(text, 18)) / 2, h / 2 + 28, 18, "#ffd060")
  end
end)
