-- Mixins Lab: the open side of modding.
--
-- Hooks (hooks.on) are the game's friendly event points. Beyond them, every
-- behaviour proc of the game is moddable: a mixin wraps it, so your code runs
-- around (or instead of) the game's own. engine.<module>.<proc> calls any of
-- the game's procs, rl.* is raylib itself, and the whole Lua standard library
-- (io, os, require...) is there. API.md, next to MODDING.md in the mods
-- folder, lists all of it with the exact signatures; MODS.EXE's Console tab
-- is the place to try things out (mixin.signature("combat.damageEnemy")).

local util = require("util")   -- util.lua, next to this file

-- 1. Wrap the game's damage door: +25% against bosses. `orig` is the game's
-- own damageEnemy (or the next mod's wrap): call it, change what it gets or
-- returns, or don't call it at all.
local boosted = 0
mixin.wrap("combat.damageEnemy", function(orig, enemy, amount, consumesShield)
  if enemy.isBoss then
    amount = amount * 1.25
    boosted = boosted + 1
  end
  return orig(enemy, amount, consumesShield)
end)

-- 2. Look at every power-up offer the game rolls. mixin.after gets the result
-- first; returning something else would replace it (nil keeps it).
local offers, lastOffer = 0, ""
mixin.after("powerup.generatePowerUpChoices", function(choices, player, isLegendary, families, mode)
  offers = offers + 1
  local names = {}
  for i, c in ipairs(choices) do names[i] = c.powerType end
  lastOffer = table.concat(names, ", ")
end)

-- 3. A file in the mod's own data folder (writing into the mod's folder would
-- change its fingerprint, and with it the save slots of modded runs).
local statsFile = mod.dataDir() .. "/runs.txt"
local runs = tonumber(util.readFile(statsFile) or "0") or 0
hooks.on("runStart", function(game, resumed)
  if resumed then return end
  runs = runs + 1
  util.writeFile(statsFile, tostring(runs))
end)

-- 4. A minimap drawn with raylib into a render texture. It is drawn in the
-- `frame` hook, at the top of the frame: no texture mode is open there (the
-- game's own drawing has not started), so rl.beginTextureMode is safe.
-- The render texture is a handle: dropped, it is unloaded by itself.
local MapW, MapH = 160, 120
local map
hooks.on("frame", function(state, dt)
  local game = engine.globals.game
  if state ~= "gsPlaying" or game == nil or game.mode == "gmPvP" then return end
  map = map or rl.loadRenderTexture(MapW, MapH)
  rl.beginTextureMode(map)
  rl.clearBackground({r = 10, g = 14, b = 22, a = 210})
  local sx, sy = MapW / game.screenWidth, MapH / game.screenHeight
  for _, e in ipairs(game.enemies) do
    rl.drawCircle(math.floor(e.x * sx), math.floor(e.y * sy), e.isBoss and 4 or 2,
                  e.isBoss and rl.Red or rl.Orange)
  end
  rl.drawCircle(math.floor(game.player.x * sx), math.floor(game.player.y * sy), 3, rl.SkyBlue)
  rl.endTextureMode()
end)

hooks.on("drawHud", function(game, w, h)
  if not map then return end
  local ax, ay, aw, ah = draw.arena()
  -- raylib's DrawTextureRec: functions keep their Nim names, and overloads
  -- share one (rl.drawTexture takes a position, a source rectangle...; API.md
  -- lists each). A render texture is stored upside down: a negative height
  -- flips it back.
  -- (bottom right: the 4:3 HUD's cards hold the top corners)
  rl.drawTexture(map.texture, {x = 0, y = 0, width = MapW, height = -MapH},
                 {x = ax + aw - MapW - 10, y = ay + ah - MapH - 10}, rl.White)
end)

-- 5. A screen of the mod's own (a state of the game, like the desktop or a
-- run). F7 opens it from anywhere but a PvP match; over a run, the run holds
-- still underneath until Esc brings it back.
register.screen{
  id = "lab",
  enter = function(from) mod.log("lab opened over " .. from) end,
  update = function(dt)
    local game = engine.globals.game
    -- engine.<module>.<proc>: any of the game's procs, here player.heal
    if rl.isKeyPressed("H") and game and game.player then
      engine.player.heal(game.player, 1)
    end
  end,
  draw = function(w, h)
    rl.drawRectangle(0, 0, w, h, {r = 8, g = 10, b = 16, a = 255})
    local lines = {
      "MIXINS LAB",
      "",
      "Boss hits boosted by the damageEnemy mixin: " .. boosted,
      "Power-up offers seen: " .. offers,
      "Last offer: " .. (lastOffer ~= "" and lastOffer or "-"),
      "Runs started with this mod: " .. runs,
      "",
      "[H] heal 1 HP (engine.player.heal)    [Esc] back",
    }
    for i, line in ipairs(lines) do
      draw.text(line, 60, 60 + (i - 1) * 28, i == 1 and 28 or 16, i == 1 and "#00e1ff" or "#d0dae6")
    end
  end,
}

hooks.on("frame", function(state)
  if state ~= "gsModScreen" and state ~= "gsPvPPlaying" and rl.isKeyPressed("F7") then
    screens.go("lab")
  end
end)

mod.log("Mixins Lab is ready: F7 opens its screen")
