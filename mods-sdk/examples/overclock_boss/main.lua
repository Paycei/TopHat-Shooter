-- Overclock: a boss with scripted attacks, movement and body.

local spin = 0

local BOSS = register.boss{
  name = "OVERCLOCK", process = "overclock.sys",
  hp = 700, speed = 70, damage = 2, radius = 40, color = "#ff5a3c",
  slotWave = 10,
  phases = {
    {name = "SPIN UP", behavior = "circle_player", attacks = {
      {type = "mod:ring", cooldown = 2.2, damage = 1, projectileCount = 14, projectileSpeed = 170},
      {type = "bapTargeted", cooldown = 1.6, damage = 1, projectileCount = 3, projectileSpeed = 230},
    }},
    {name = "MELTDOWN", hpThreshold = 0.5, speedMultiplier = 1.3, behavior = "mod:dash",
     attacks = {
      {type = "mod:ring", cooldown = 1.3, damage = 2, projectileCount = 20, projectileSpeed = 200},
      {type = "bapBarrage", cooldown = 2.6, damage = 1},
    }},
  },
  attacks = {
    -- A ring of bullets whose starting angle keeps turning, so the gaps move.
    ring = function(boss, attack, game)
      spin = spin + 0.35
      for i = 1, attack.projectileCount do
        local a = spin + i / attack.projectileCount * math.pi * 2
        spawn.bullet{x = boss.x, y = boss.y,
                     vx = math.cos(a) * attack.projectileSpeed,
                     vy = math.sin(a) * attack.projectileSpeed,
                     damage = attack.damage, radius = 6, color = "#ff8a3c"}
      end
      fx.sound("explosion", 0.4, 1.4)
    end,
  },
  behaviors = {
    -- Phase 2: lunge at the player every two seconds, drifting in between.
    dash = function(boss, dt, game)
      run.data.dashClock = (run.data.dashClock or 0) + dt
      if run.data.dashClock > 2 then
        run.data.dashClock = 0
        local dx, dy = player.x - boss.x, player.y - boss.y
        local d = math.max(1, math.sqrt(dx * dx + dy * dy))
        boss.vx, boss.vy = dx / d * 520, dy / d * 520
      else
        boss.vx, boss.vy = boss.vx * 0.94, boss.vy * 0.94
      end
      boss.x = boss.x + boss.vx * dt
      boss.y = boss.y + boss.vy * dt
    end,
  },
  draw = function(boss)
    local t = game.time
    draw.circle(boss.x, boss.y, boss.radius + 8, "#3a0e0655")
    draw.poly(boss.x, boss.y, 8, boss.radius, t * 60, "#ff5a3c")
    draw.poly(boss.x, boss.y, 8, boss.radius * 0.72, -t * 120, "#2a0a06")
    draw.circle(boss.x, boss.y, boss.radius * 0.3 + math.sin(t * 8) * 3, "#ffd28a")
  end,
}

-- Wave mode's boss at wave 10 becomes Overclock.
hooks.on("bossForWave", function(bossId, game, wave)
  if game:isMode("wave") and wave == 10 then return BOSS end
end)

mods.export({bossId = BOSS})
