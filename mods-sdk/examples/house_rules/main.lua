-- House Rules: a mode that replaces parts of how the game works.
--
-- Every hook runs for every run, so each rule first checks it is this mode's.

local MODE = register.gamemode{
  id = "house_rules",
  name = {en = "House Rules", es = "Reglas de la Casa"},
  description = {
    en = "Dash blinks, coins heal, half-price shop, level-ups sharpen your shots.",
    es = "El impulso teletransporta, las monedas curan, tienda a mitad de precio, subir de nivel afila tus disparos.",
  },
  base = "wave",
  onStart = function(game, resumed)
    -- Deep access: game.shopItems is the game's own list of shop items.
    if not resumed then
      for _, item in ipairs(game.shopItems) do
        item.baseCost = math.max(1, math.floor(item.baseCost / 2))
      end
    end
    -- This mode draws its own run panel (see drawHud below).
    hud.hide("run")
    hud.hide("combo")
  end,
}

local function active()
  return run.active and game:isMode(MODE)
end

local function say(en, es) return lang.current() == "es" and es or en end

-- Dash becomes a blink toward the mouse. Returning true skips the built-in
-- dash; setting the player's own dashCooldown keeps the HUD's dash meter right.
hooks.on("dash", function(p)
  if not active() then return end
  local mx, my = input.mouse()
  local dx, dy = mx - p.x, my - p.y
  local dist = math.sqrt(dx * dx + dy * dy)
  if dist < 1 then return true end
  local reach = math.min(dist, 170)
  fx.particles(p.x, p.y, "#b48cff", 16)
  p.x = math.clamp(p.x + dx / dist * reach, p.radius, game.screenWidth - p.radius)
  p.y = math.clamp(p.y + dy / dist * reach, p.radius, game.screenHeight - p.radius)
  p.dashCooldown = 1.1
  p.invincibilityTimer = math.max(p.invincibilityTimer, 0.25)
  fx.particles(p.x, p.y, "#b48cff", 16)
  fx.sound("teleport", 0.4, 1.3)
  return true
end)

-- Coins still pay, and patch you up a little. Returning true means "handled":
-- the built-in pickup (and its reward) is skipped, so we pay the coins ourselves.
hooks.on("pickup", function(kind, value, game)
  if not active() or kind ~= "coin" then return end
  player.coins = player.coins + value
  player:heal(0.25 * value)
  fx.sound("coinPickup", 0.5, 1.2)
  return true
end)

-- Every level-up: +4% damage and slightly bigger shots from here on.
hooks.on("levelUp", function(game, level)
  if not active() then return end
  player.damage = player.damage * 1.04
  run.data.shotScale = (run.data.shotScale or 1) * 1.03
end)

hooks.on("bulletSpawn", function(b)
  if active() and b.fromPlayer and run.data.shotScale then
    b.radius = b.radius * run.data.shotScale
  end
end)

-- The mode's own run panel, in place of the hidden built-in one.
hooks.on("drawHud", function(game, w, h)
  if not active() then return end
  local ax, ay, aw = draw.arena()
  local x, y = ax + aw - 196, ay + 10
  draw.rect(x, y, 186, 78, "#0c1018cc")
  draw.rectLines(x, y, 186, 78, "#b48cff", 1)
  draw.text(say("HOUSE RULES", "REGLAS DE LA CASA"), x + 10, y + 8, 12, "#b48cff")
  draw.text(say("Wave ", "Oleada ") .. game.currentWave, x + 10, y + 26, 16, "#e8ecf4")
  local left = #game.enemies + game.waveEnemiesRemaining
  draw.text(say("Processes left: ", "Procesos restantes: ") .. left, x + 10, y + 46, 12, "#9aa6b8")
  draw.text(say("Shot size x", "Disparo x") .. string.format("%.2f", run.data.shotScale or 1),
            x + 10, y + 60, 12, "#9aa6b8")
end)
