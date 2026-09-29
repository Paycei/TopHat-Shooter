-- Model Pack: 3D models. Cosmetics to equip in MODS.EXE > Cosmetics, and a
-- Model Viewer app in MODS.EXE > Apps that shows every model here and can
-- swap the Circle enemies for an animated drone.
--
-- Models come from your mod folder: GLB/glTF (Blender's glTF export), OBJ
-- (with its .mtl), IQM, VOX (MagicaVoxel) or M3D. Their front is +Z and their
-- up +Y, which is how Blender's glTF export writes them.

local ship  = assets.model("ship.glb")        -- a low-poly ship
local drone = assets.model("drone.glb")       -- skinned, animations "hover" and "spin"
local bolt  = assets.model("bolt.obj")        -- an OBJ, coloured by bolt.mtl
local cube  = assets.model("data_cube.vox")   -- a MagicaVoxel model

register.cosmetic{
  kind = "player", id = "arrow",
  name = {en = "Arrow (3D)", es = "Flecha (3D)"},
  description = {en = "A low-poly ship that turns its nose to where you move.",
                 es = "Una nave low-poly que gira el morro hacia donde te mueves."},
  model = ship, rotate = true,   -- its front (+Z) turns to where you move
  tilt = 25,                     -- lean the camera back to show its sides
}

register.cosmetic{
  kind = "bullet", id = "bolt",
  name = {en = "Energy Bolt (3D)", es = "Rayo de Energía (3D)"},
  model = bolt, rotate = true, scale = 1.8,
  lit = false,                   -- flat colours: a bolt glows, it is not shaded
}

register.cosmetic{
  kind = "desktop", id = "data_cube",
  name = {en = "Data Cube (3D)", es = "Cubo de Datos (3D)"},
  description = {en = "A voxel cube in place of the desktop cube. Drag it to spin it.",
                 es = "Un cubo de vóxeles en lugar del cubo del escritorio. Arrástralo para girarlo."},
  model = cube,                  -- no texture: the wallpaper stays as it is
}

-- The drones, only once the player asks for them in the app (so the Circles
-- another mod may have restyled stay theirs). nil puts the game's look back.
local settings = mod.storage
local function applyDrones()
  override.model("enemy:etCircle", settings.drones and drone or nil,
                 {animation = "hover", tilt = 30, scale = 1.6})
end
if settings.drones then applyDrones() end

local function say(en, es) return lang.current() == "es" and es or en end

-- MODS.EXE > Apps > Model Viewer: every model on a turntable. Click the drone
-- to switch its animation; the box below swaps the Circle enemies for drones.
local shown = {
  {file = "ship.glb", model = ship},
  {file = "drone.glb", model = drone, anim = 1},
  {file = "bolt.obj", model = bolt},
  {file = "data_cube.vox", model = cube},
}
local PAD = 20
local BOX_H = 18
local turn = 0

local function cellWidth(w) return (w - PAD * 2) / #shown end

register.app{
  id = "viewer",
  name = {en = "Model Viewer", es = "Visor de Modelos"},
  icon = ship,              -- the desktop icon shows the ship turning
  color = "#7de2ff",        -- accent of the icon tile and the window
  width = 560, height = 340,
  update = function(dt) turn = turn + dt * 40 end,   -- degrees per second
  draw = function(w, h, mx, my)
    draw.text(say("MODEL VIEWER", "VISOR DE MODELOS"), PAD, 16, 20, "#7de2ff")
    local cw = cellWidth(w)
    local size = math.min(cw * 0.7, h * 0.35)
    for i, s in ipairs(shown) do
      local cx = PAD + cw * (i - 0.5)
      local cy = 60 + size * 0.7
      local names = s.model.animations
      draw.model(s.model, cx, cy, {
        size = size, facing = 90 + turn, tilt = 30,
        animation = s.anim and names[s.anim] or false,
      })
      local label = s.file
      draw.text(label, cx - draw.textWidth(label, 12) / 2, cy + size * 0.75, 12, "#e0e8f0")
      if #names > 0 then
        local a = say("click: ", "clic: ") .. names[s.anim]
        draw.text(a, cx - draw.textWidth(a, 11) / 2, cy + size * 0.75 + 16, 11, "#8a96a6")
      end
    end
    local by = h - 44
    local hover = mx >= PAD and mx <= PAD + BOX_H and my >= by and my <= by + BOX_H
    draw.rectLines(PAD, by, BOX_H, BOX_H, hover and "#ffffff" or "#7de2ff", 1)
    if settings.drones then draw.rect(PAD + 4, by + 4, BOX_H - 8, BOX_H - 8, "#7de2ff") end
    draw.text(say("Drones replace the Circle enemies", "Drones en lugar de los enemigos Círculo"),
              PAD + BOX_H + 10, by + 2, 14, "#e0e8f0")
  end,
  click = function(x, y, button, w, h)
    local by = h - 44
    if x >= PAD and x <= PAD + BOX_H and y >= by and y <= by + BOX_H then
      settings.drones = not settings.drones
      applyDrones()
      mod.saveStorage()
      return
    end
    local i = math.floor((x - PAD) / cellWidth(w)) + 1
    local s = shown[i]
    if s and s.anim then
      s.anim = s.anim % #s.model.animations + 1   -- the next animation
    end
  end,
}
