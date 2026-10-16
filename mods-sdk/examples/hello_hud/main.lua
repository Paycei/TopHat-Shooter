-- Hello HUD: the smallest useful mod.
--
-- Every mod is a folder with a mod.json and a main script. The main script
-- runs once when the mod loads (from the MODS.EXE window); it registers
-- functions with hooks.on, and the game calls them while you play.

-- A key of our own. Players rebind it in Settings > Controls > Mod Keybinds.
register.keybind{
  id = "ring",
  name = {en = "Toggle ring", es = "Mostrar anillo"},
  default = "f6",
  gamepad = "RightFaceUp",
}

local showRing = true

hooks.on("runStart", function(game, resumed)
  mod.log(resumed and "run resumed" or "run started")
end)

-- run.data is saved with the run, so this clock survives quitting and resuming.
hooks.on("update", function(game, dt)
  run.data.time = (run.data.time or 0) + dt
  if input.bindPressed("ring") then showRing = not showRing end
end)

-- drawWorld draws in arena coordinates: the same space as player.x/y.
hooks.on("drawWorld", function(game)
  if not showRing then return end
  local p = game.player
  local pulse = 4 * math.sin((run.data.time or 0) * 4)
  draw.circleLines(p.x, p.y, p.radius + 16 + pulse, {r = 255, g = 204, b = 51, a = 150}, 2)
end)

-- drawHud draws in screen coordinates; w and h are the screen size.
-- draw.arena() says where the arena is, so the readout stays clear of the
-- side panels in widescreen: here it sits centred near the arena's bottom.
hooks.on("drawHud", function(game, w, h)
  local ax, ay, aw, ah = draw.arena()
  local line = string.format("HELLO HUD   kills %d   time %d s   [F6] ring",
                             game.player.kills, math.floor(run.data.time or 0))
  local width = draw.textWidth(line, 12)
  local x = ax + (aw - width) / 2
  local y = ay + ah - 70
  draw.rect(x - 8, y - 5, width + 16, 22, "#10131acc")
  draw.text(line, x, y, 12, "#ffcc33")
end)

mod.log("Hello HUD is ready")
