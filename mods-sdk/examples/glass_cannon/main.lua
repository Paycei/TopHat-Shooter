-- Glass Cannon: a whole game mode built on wave mode.
--
-- register.gamemode adds it to MODS.EXE > Game Modes. The hooks below run for
-- every run, so each one first checks that this mode is the one being played.

local MODE = register.gamemode{
  id = "glass_cannon",
  name = {en = "Glass Cannon", es = "Cañón de Cristal"},
  description = {
    en = "Double damage dealt, triple damage taken, twice the enemies, no healing.",
    es = "Doble de daño infligido, triple de daño recibido, el doble de enemigos, sin curación.",
  },
  base = "wave",
  onStart = function(game, resumed)
    if not resumed then
      run.data.startDamage = player.damage
      player.damage = player.damage * 2
    end
  end,
}

local function active()
  return run.active and game:isMode(MODE)
end

hooks.on("waveEnemyCount", function(count)
  if active() then return count * 2 end
end)

hooks.on("playerDamaged", function(amount)
  if active() then return amount * 3 end
end)

hooks.on("playerHeal", function(amount)
  if active() then return 0 end
end)

hooks.on("waveEnd", function(game, wave)
  if active() then run.data.cleared = wave end
end)

hooks.on("drawHud", function(game, w, h)
  if not active() then return end
  local ax, ay, aw, ah = draw.arena()
  local text = lang.current() == "es" and "OLEADAS SUPERADAS: " or "WAVES CLEARED: "
  local line = text .. (run.data.cleared or 0)
  local width = draw.textWidth(line, 12)
  draw.text(line, ax + aw - width - 14, ay + ah - 40, 12, "#ff7a7a")
end)
