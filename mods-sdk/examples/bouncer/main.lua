-- Bouncer: a new enemy with its own movement and look, plus a power-up.

local BOUNCER = register.enemy{
  id = "bouncer",
  name = "bouncer",              -- its in-world process label
  base = "etCircle",             -- starting stats and AI (overridden below)
  hp = 3, radius = 12, speed = 150, contactDamage = 2,
  color = "#4ad8ff", coins = 3, xp = 2,
  update = function(e, dt, game)
    -- Fly straight and bounce off the arena edges; returning true replaces
    -- the base type's AI for this frame.
    if e.vx == 0 and e.vy == 0 then
      local a = math.random() * math.pi * 2
      e.vx, e.vy = math.cos(a) * e.speed, math.sin(a) * e.speed
    end
    local x, y = e.x + e.vx * dt, e.y + e.vy * dt
    if x < e.radius or x > game.screenWidth - e.radius then e.vx = -e.vx end
    if y < e.radius or y > game.screenHeight - e.radius then e.vy = -e.vy end
    e.x = math.clamp(x, e.radius, game.screenWidth - e.radius)
    e.y = math.clamp(y, e.radius, game.screenHeight - e.radius)
    return true
  end,
  draw = function(e)
    draw.poly(e.x, e.y, 4, e.radius + 3, game.time * 240, "#0b2a3a")
    draw.poly(e.x, e.y, 4, e.radius, game.time * 240, "#4ad8ff")
    draw.circle(e.x, e.y, e.radius * 0.35, "#e8fbff")
  end,
}
roster.add("wave", BOUNCER, {chance = 0.2, fromWave = 3})

local PULSE = register.powerup{
  id = "pulse_core",
  name = "PULSE_CORE.exe",
  description = {
    en = {"Every 4 s: shock enemies within 140 px",
          "Every 3 s: shock enemies within 170 px",
          "Every 2 s: shock enemies within 200 px"},
    es = {"Cada 4 s: descarga a los enemigos a 140 px",
          "Cada 3 s: descarga a los enemigos a 170 px",
          "Cada 2 s: descarga a los enemigos a 200 px"},
  },
  maxLevel = 3, color = "#7df9ff", family = "lightning",
  modes = {"wave", "survival", "roguelite"},
  icon = function(color)
    draw.circleLines(16, 16, 12, color, 2)
    draw.circleLines(16, 16, 7, color, 2)
    draw.circle(16, 16, 3, "#ffffff")
  end,
  -- Runs every frame while the player has it. Damage and healing done in here
  -- count as this power-up's in the run statistics.
  update = function(player, level, dt, game)
    run.data.pulseClock = (run.data.pulseClock or 0) + dt
    local every = ({4, 3, 2})[level]
    if run.data.pulseClock < every then return end
    run.data.pulseClock = 0
    local radius = ({140, 170, 200})[level]
    for _, e in ipairs(game:enemiesNear(player.x, player.y, radius)) do
      local dealt = e:damage(player.damage * 0.8)
      fx.damageNumber(e.x, e.y, dealt)
    end
    fx.particles(player.x, player.y, "#7df9ff", 30)
    fx.sound("teleport", 0.5, 1.6)
  end,
}
