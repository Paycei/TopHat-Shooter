-- Retro CRT: a post-processing shader, and an app to tune it.
--
-- override.shader("game", ...) runs the shader over every frame while a run is
-- on screen; "screen" would cover the desktop too. The settings live in
-- mod.storage, so they are remembered for this profile between sessions.

local crt = assets.shader("crt.fs")

local settings = mod.storage
settings.strength = settings.strength or 0.6
if settings.everywhere == nil then settings.everywhere = false end

local function apply()
  crt:set("strength", settings.strength)
  override.shader("game", crt)
  override.shader("screen", settings.everywhere and crt or nil)
end
apply()

local function say(en, es) return lang.current() == "es" and es or en end

-- MODS.EXE > Apps > CRT Settings. Everything is in canvas coordinates: draw()
-- gets the canvas size and the mouse inside it (-1 when outside), click()
-- gets the click and the canvas size.
local PAD = 24
local SLIDER_Y = 86
local BOX_Y = 150

register.app{
  id = "settings",
  name = {en = "CRT Settings", es = "Ajustes CRT"},
  color = "#7dffb0",        -- accent of the desktop icon and the window
  width = 420, height = 240,
  draw = function(w, h, mx, my)
    local sliderW = w - PAD * 2
    draw.text(say("RETRO CRT", "CRT RETRO"), PAD, 20, 20, "#7dffb0")
    draw.text(say("Strength", "Intensidad"), PAD, 60, 14, "#e0e8f0")
    draw.text(math.round(settings.strength * 100) .. "%", w - PAD - 40, 60, 14, "#7dffb0")
    draw.rect(PAD, SLIDER_Y, sliderW, 8, "#1c2430")
    draw.rect(PAD, SLIDER_Y, sliderW * settings.strength, 8, "#3fbf7f")
    draw.circle(PAD + sliderW * settings.strength, SLIDER_Y + 4, 9, "#e8fff2")

    local hover = mx >= PAD and mx <= PAD + 18 and my >= BOX_Y and my <= BOX_Y + 18
    draw.rectLines(PAD, BOX_Y, 18, 18, hover and "#ffffff" or "#7dffb0", 1)
    if settings.everywhere then draw.rect(PAD + 4, BOX_Y + 4, 10, 10, "#7dffb0") end
    draw.text(say("Also on the desktop", "También en el escritorio"), PAD + 28, BOX_Y + 2, 14, "#e0e8f0")

    draw.text(say("Click the bar to set the strength.", "Pulsa la barra para fijar la intensidad."),
              PAD, h - 40, 12, "#8a96a6")
  end,
  click = function(x, y, button, w, h)
    if y >= SLIDER_Y - 10 and y <= SLIDER_Y + 18 then
      settings.strength = math.clamp((x - PAD) / (w - PAD * 2), 0, 1)
    elseif x >= PAD and x <= PAD + 18 and y >= BOX_Y and y <= BOX_Y + 18 then
      settings.everywhere = not settings.everywhere
    else
      return
    end
    apply()
    mod.saveStorage()
  end,
}
