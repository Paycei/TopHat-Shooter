-- Necromancer: statuses, allied things and mod events.
--
-- * Every player bullet that lands adds a stack of SOUL BURN (a status of
--   ours): it burns, slows and makes the enemy take more damage.
-- * An enemy that dies with Soul Burn on it may rise as a THRALL (a thing on
--   the player's team) that chases the nearest enemy and claws it.
-- * Other mods can join in through our events (see the end of the file).

local PURPLE = "#a040ff"

local SOUL = register.status{
  id = "soulBurn",
  name = {en = "Soul Burn", es = "Quemadura de Alma"},
  color = PURPLE,
  maxStacks = 5, duration = 4, tickInterval = 0.5,
  modifiers = {speed = -0.06, damageTaken = 0.05},   -- per stack
  onTick = function(e, stacks) e:damage(0.15 * stacks) end,
}

local THRALL = register.thing{
  id = "thrall",
  team = "player", motion = "chaseEnemy", speed = 150,
  shape = "circle", radius = 11, color = PURPLE,
  hp = 6, hitByBullets = true,              -- the enemies' shots wear it down
  contactDamage = 1.2, contactInterval = 0.4,
  lifetime = 18,
  draw = function(t)
    local pulse = 0.5 + 0.5 * math.sin(game.time * 6 + t.id)
    draw.circle(t.x, t.y, t.radius, "#2a1040")
    draw.circleLines(t.x, t.y, t.radius, PURPLE, 2)
    draw.circle(t.x - 4, t.y - 2, 2 + pulse, "#ff60ff")
    draw.circle(t.x + 4, t.y - 2, 2 + pulse, "#ff60ff")
  end,
  onDeath = function(t) fx.particles(t.x, t.y, PURPLE, 14) end,
  onExpire = function(t) fx.particles(t.x, t.y, "#6040a0", 8) end,
}

hooks.on("runStart", function(game, resumed)
  if not resumed then run.data = {raised = 0, souls = 0} end
end)

hooks.on("bulletHit", function(dmg, b, e)
  e:applyStatus(SOUL)
end)

hooks.on("enemyDeath", function(e, game)
  if e.isBoss then return end
  local burn = e:status(SOUL)
  if not burn then return end
  local souls = hooks.filter("necromancer:soulValue", burn.stacks, e)
  run.data.souls = (run.data.souls or 0) + souls
  -- 10% per stack, and other mods may change it
  local chance = hooks.filter("necromancer:raiseChance", 0.1 * burn.stacks, e)
  if #game:things(THRALL) < 12 and math.random() < chance then
    local ally = spawn.thing(THRALL, e.x, e.y)
    ally.data.from = e.enemyType
    run.data.raised = (run.data.raised or 0) + 1
    fx.particles(e.x, e.y, PURPLE, 24)
    hooks.emit("necromancer:raised", ally, e)
  end
end)

hooks.on("drawHud", function(game, w, h)
  if not run.data.raised then return end
  local ax, ay, aw, ah = draw.arena()
  local label = lang.current() == "es" and "SIERVOS: " or "THRALLS: "
  draw.text(label .. #game:things(THRALL) .. "  (" .. run.data.raised .. ")",
            ax + 14, ay + ah - 40, 12, PURPLE)
end)

-- Other mods: mods.get("necromancer").SOUL / .THRALL, and
--   hooks.on("necromancer:raised", function(ally, enemy) ... end)
--   hooks.on("necromancer:raiseChance", function(chance, enemy) return chance * 2 end)
--   hooks.on("necromancer:soulValue", function(souls, enemy) return souls + 1 end)
mods.export({SOUL = SOUL, THRALL = THRALL})
