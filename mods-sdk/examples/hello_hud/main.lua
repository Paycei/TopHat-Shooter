-- Hello HUD: the smallest useful mod.
--
-- Every mod is a folder with a mod.json and a main script. The main script
-- runs once when the mod loads (from the MODS.EXE window); it registers
-- functions with hooks.on, and the game calls them while you play.

-- run.data is saved with the run, so this survives quitting and resuming.
hooks.on("runStart", function(game, resumed)
  run.data.starts = (run.data.starts or 0) + 1
  mod.log("run started", resumed and "(resumed)" or "(fresh)",
          "starts so far:", run.data.starts)
end)

local elapsed = 0

hooks.on("update", function(game, dt)
  elapsed = elapsed + dt
end)

-- drawWorld draws in arena coordinates: the same space as player.x/y.
hooks.on("drawWorld", function(game)
  local p = game.player
  local pulse = 4 * math.sin(elapsed * 4)
  draw.circleLines(p.x, p.y, p.radius + 16 + pulse, {r = 255, g = 204, b = 51, a = 150}, 2)
end)

-- drawHud draws in screen coordinates; w and h are the screen size.
-- draw.arena() says where the arena is, so the readout stays clear of the
-- side panels in widescreen: here it sits centred near the arena's bottom.
hooks.on("drawHud", function(game, w, h)
  local ax, ay, aw, ah = draw.arena()
  local line = string.format("HELLO HUD   kills %d   time %d s", game.player.kills, math.floor(elapsed))
  local width = draw.textWidth(line, 12)
  local x = ax + (aw - width) / 2
  local y = ay + ah - 70
  draw.rect(x - 8, y - 5, width + 16, 22, "#10131acc")
  draw.text(line, x, y, 12, "#ffcc33")
end)

mod.log("Hello HUD is ready")
