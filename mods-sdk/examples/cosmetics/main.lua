-- Cosmetics Pack: looks only. Nothing here changes how a run plays, so
-- mod.json sets "disableAchievements": false and runs keep their rewards.
--
-- * Cosmetics to equip in MODS.EXE > Cosmetics (remembered per profile):
--   player skins (a palette, an animated GIF, a 3D model), bullets (a palette,
--   a 3D model), a wallpaper and a 3D desktop cube.
-- * A CRT post-processing shader (crt.fs) and a desktop app to tune it, which
--   can also swap the Circle enemies for an animated 3D drone.
--
-- Models come from your mod folder: GLB/glTF (Blender's glTF export), OBJ
-- (with its .mtl), IQM, VOX (MagicaVoxel) or M3D. Their front is +Z and their
-- up +Y, which is how Blender's glTF export writes them.

local function say(en, es) return lang.current() == "es" and es or en end

local ship  = assets.model("ship.glb")    -- a low-poly ship
local drone = assets.model("drone.glb")   -- skinned, with the animations "hover" and "spin"
local crt   = assets.shader("crt.fs")

-- ------------------------------------------------------------- cosmetics ----
register.cosmetic{
  kind = "player", id = "neon_pulse",
  name = {en = "Neon Pulse", es = "Pulso de Neón"},
  description = {en = "Magenta body, cyan trim.", es = "Cuerpo magenta, bordes cian."},
  colors = {"#ff2bd6", "#2bf0ff", "#ffffff"},   -- body, trim, core
}

register.cosmetic{
  kind = "player", id = "neon_core",
  name = {en = "Neon Core", es = "Núcleo de Neón"},
  description = {en = "An animated GIF: two sparks orbit a pulsing core.",
                 es = "Un GIF animado: dos chispas orbitan un núcleo que late."},
  texture = "neon_core.gif",   -- a GIF plays by itself, at the speed saved in it
  scale = 1.4, rotate = true,  -- a bit bigger; the nose turns to where you move
}

register.cosmetic{
  kind = "player", id = "arrow",
  name = {en = "Arrow (3D)", es = "Flecha (3D)"},
  description = {en = "A low-poly ship that turns its nose to where you move.",
                 es = "Una nave low-poly que gira el morro hacia donde te mueves."},
  model = ship, rotate = true,   -- its front (+Z) turns to where you move
  tilt = 25,                     -- lean the camera back to show its sides
}

register.cosmetic{
  kind = "bullet", id = "neon_trail",
  name = {en = "Neon Trail", es = "Estela de Neón"},
  colors = {"#2bf0ff", "#ff2bd6", "#7a3cff"},   -- body, glow, trail
}

register.cosmetic{
  kind = "bullet", id = "bolt",
  name = {en = "Energy Bolt (3D)", es = "Rayo de Energía (3D)"},
  model = assets.model("bolt.obj"),   -- an OBJ, coloured by bolt.mtl
  rotate = true, scale = 1.8,
  lit = false,                        -- flat colours: a bolt glows, it is not shaded
}

register.cosmetic{
  kind = "desktop", id = "neon_grid",
  name = {en = "Neon Grid", es = "Rejilla de Neón"},
  texture = "wallpaper.png",
  cube = true,   -- keep the desktop cube floating over the wallpaper
}

register.cosmetic{
  kind = "cube", id = "data_cube",
  name = {en = "Data Cube (3D)", es = "Cubo de Datos (3D)"},
  description = {en = "A voxel cube in place of the desktop cube. Drag it to spin it.",
                 es = "Un cubo de vóxeles en lugar del cubo del escritorio. Arrástralo para girarlo."},
  model = assets.model("data_cube.vox"),   -- a MagicaVoxel model
}

-- -------------------------------------------------------------- settings ----
-- mod.storage is kept between sessions, per profile.
local settings = mod.storage
settings.crt = settings.crt or 0   -- the CRT's strength: 0 is off

local function applyCrt()
  -- "game" runs the shader over every frame of a run; "screen" covers the
  -- desktop too. nil takes it off.
  local on = settings.crt > 0 and crt or nil
  crt:set("strength", settings.crt)
  override.shader("game", on)
  override.shader("screen", settings.crtDesktop and on or nil)
end
applyCrt()

-- The drones go on only once the player asks for them, so Circles another
-- mod has restyled stay theirs. nil puts the game's look back.
local function applyDrones()
  override.model("enemy:etCircle", settings.drones and drone or nil,
                 {animation = "hover", tilt = 30, scale = 1.6})
end
if settings.drones then applyDrones() end

-- ------------------------------------------------------------------- app ----
-- MODS.EXE > Apps > Cosmetics Pack, also on the desktop. Everything is in
-- canvas coordinates: draw() gets the canvas size and the mouse inside it
-- (-1 when outside), click() and drag() get the pointer.
local PAD, SLIDER_Y, SLIDER_W = 24, 76, 240
local BOXES = {
  {key = "crtDesktop", y = 112, text = {"CRT on the desktop too", "CRT también en el escritorio"}, apply = applyCrt},
  {key = "drones", y = 142, text = {"Drones replace the Circle enemies", "Drones en lugar de los enemigos Círculo"},
   apply = applyDrones},
}
local turn = 0

local function onSlider(y) return y >= SLIDER_Y - 10 and y <= SLIDER_Y + 18 end
local function setStrength(x)
  settings.crt = math.clamp((x - PAD) / SLIDER_W, 0, 1)
  applyCrt()
  mod.saveStorage()
end

register.app{
  id = "settings",
  name = {en = "Cosmetics Pack", es = "Paquete Estético"},
  icon = ship,              -- a model icon: the desktop icon shows the ship turning
  color = "#7de2ff",        -- accent of the icon tile and the window
  width = 460, height = 230,
  update = function(dt) turn = turn + dt * 40 end,   -- degrees per second
  draw = function(w, h, mx, my)
    draw.text(say("COSMETICS PACK", "PAQUETE ESTÉTICO"), PAD, 18, 20, "#7de2ff")
    draw.text(say("CRT filter", "Filtro CRT"), PAD, 50, 14, "#e0e8f0")
    local value = settings.crt > 0 and math.round(settings.crt * 100) .. "%" or say("OFF", "NO")
    draw.text(value, PAD + SLIDER_W - draw.textWidth(value, 14), 50, 14, "#7de2ff")
    draw.rect(PAD, SLIDER_Y, SLIDER_W, 8, "#1c2430")
    draw.rect(PAD, SLIDER_Y, SLIDER_W * settings.crt, 8, "#3f9fbf")
    draw.circle(PAD + SLIDER_W * settings.crt, SLIDER_Y + 4, 9, "#e8f8ff")
    for _, b in ipairs(BOXES) do
      draw.rectLines(PAD, b.y, 18, 18, "#7de2ff", 1)
      if settings[b.key] then draw.rect(PAD + 4, b.y + 4, 10, 10, "#7de2ff") end
      draw.text(say(b.text[1], b.text[2]), PAD + 28, b.y + 2, 14, "#e0e8f0")
    end
    draw.text(say("Equip the skins in MODS.EXE > Cosmetics.", "Equipa los aspectos en MODS.EXE > Cosméticos."),
              PAD, h - 34, 12, "#8a96a6")
    -- draw.model draws a model in 2D, here the drone with its animation.
    draw.model(drone, w - 80, 90, {size = 100, facing = 90 + turn, tilt = 30, animation = "hover"})
  end,
  click = function(x, y, button, w, h)
    if onSlider(y) and x <= PAD + SLIDER_W + 10 then return setStrength(x) end
    for _, b in ipairs(BOXES) do
      if x >= PAD and x <= PAD + 18 and y >= b.y and y <= b.y + 18 then
        settings[b.key] = not settings[b.key]
        b.apply()
        mod.saveStorage()
      end
    end
  end,
  drag = function(x, y, w, h)
    if onSlider(y) then setStrength(x) end
  end,
}
