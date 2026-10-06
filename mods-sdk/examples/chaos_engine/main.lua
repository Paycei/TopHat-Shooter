-- Chaos Engine: hazards, camera and time, and content for every mode.

local ORANGE = "#ff8030"

local function tr(en, sp) return lang.current() == "es" and sp or en end

local SURVIVOR = register.advancement{
  id = "survivor",
  name = {en = "Chaos Survivor", es = "Superviviente del Caos"},
  description = {en = "Outlast 100 chaos hazards", es = "Resiste 100 peligros del caos"},
  goal = 100,
}

-- A random telegraphed hazard somewhere near the player. Counts toward the
-- achievement when it goes off without catching the player.
local function dropHazard(game, damage)
  local x = player.x + math.random(-220, 220)
  local y = player.y + math.random(-160, 160)
  local hp = player.hp
  local roll = math.random(3)
  local onTrigger = function()
    -- a beat later, did it hit?
    timer.after(0.35, function()
      if run.active and player.hp >= hp then advancements.progress(SURVIVOR) end
    end)
  end
  if roll == 1 then
    spawn.hazard{shape = "circle", x = x, y = y, r = 70, warn = 1.3, active = 0.3,
                 damage = damage, hurts = "all", color = ORANGE, onTrigger = onTrigger}
  elseif roll == 2 then
    spawn.hazard{shape = "line", x = x, y = y, length = 900, angle = math.random(0, 179), r = 16,
                 warn = 1.1, active = 0.6, tick = 0.3, damage = damage, hurts = "all",
                 color = ORANGE, onTrigger = onTrigger}
  else
    spawn.hazard{shape = "ring", x = player.x, y = player.y, inner = 90, r = 140, warn = 1.5,
                 active = 0.4, damage = damage, hurts = "all", color = "#ff4060", onTrigger = onTrigger}
  end
end

hooks.on("runStart", function(game, resumed)
  -- timers are cleared with every new run: start them again here
  if game:isMode("pvp") then return end
  timer.every(9, function()
    if run.active and game.state == "gsPlaying" and not game:isMode("survival") then
      dropHazard(game, 1)
    end
  end)
end)

-- bosses make an entrance, and an exit
hooks.on("bossSpawn", function(boss, game)
  camera.zoom = 1.5
  camera.follow(true, 5)
  time.slowmo(1.2, 0.35, true)
  fx.shake("large")
  timer.after(1.8, function() if run.active then camera.reset() end end)
end)

hooks.on("bossDeath", function(boss, game)
  time.hitstop(0.25)
  time.slowmo(1.5, 0.3, true)
end)

-- wave mode's shop: calms everything down a little
register.shopItem{
  id = "stabilizer",
  name = {en = "Stabilizer", es = "Estabilizador"},
  description = {en = "+2 walls, +1 integrity", es = "+2 muros, +1 de integridad"},
  cost = 10, costMult = 1.6, maxBuys = 3,
  modes = {"wave"}, minWave = 2, color = ORANGE,
  stats = {walls = 2, maxHp = 1},
  onBuy = function(player, game, bought) fx.sound("powerUp") end,
}

-- a roguelite patch: every 6 seconds the nearest enemy blows up
register.patch{
  id = "entropy",
  name = {en = "KB Entropy", es = "KB Entropía"},
  description = {en = "Every 6 s the nearest enemy explodes", es = "Cada 6 s explota el enemigo más cercano"},
  color = ORANGE, weight = 1, minFloor = 1,
  update = function(player, dt, game)
    run.data.entropy = (run.data.entropy or 0) + dt
    if run.data.entropy < 6 then return end
    local e = game:nearestEnemy(player.x, player.y, 500)
    if e then
      run.data.entropy = 0
      game:explode(e.x, e.y, 80, 3, {color = ORANGE, shake = "small"})
    end
  end,
}

-- a survival event: hazards rain for 20 s; five hits fail it
register.survivalEvent{
  id = "storm",
  name = {en = "Chaos Storm", es = "Tormenta del Caos"},
  hint = {en = "Dodge the storm: 5 hits fail it", es = "Esquiva la tormenta: 5 golpes y fallas"},
  color = ORANGE,
  weights = {boot = 0, runtime = 15, overload = 20, panic = 20},
  duration = 20, warmup = 2,
  reward = "sctStandard",
  onStart = function(ev, game) ev.data.next = 0 run.data.stormHits = 0 end,
  update = function(ev, game, dt)
    if ev.live <= 0 then return end            -- still in the warmup
    ev.data.next = ev.data.next - dt
    if ev.data.next <= 0 then
      ev.data.next = 1.4
      dropHazard(game, 1)
    end
    if (run.data.stormHits or 0) >= 5 then return "fail" end
  end,
  onFinish = function(ev, game, success) run.data.stormHits = nil end,
  tracker = function(ev, game) return (run.data.stormHits or 0) .. " / 5 " .. tr("hits", "golpes") end,
  fraction = function(ev, game) return 1 - ev.live / ev.limit end,
}

hooks.on("playerDamaged", function(amount, player)
  if run.data.stormHits then run.data.stormHits = run.data.stormHits + 1 end
end)

register.command{
  name = "chaos",
  help = {en = "Shows your Chaos Survivor progress", es = "Muestra tu progreso de Superviviente del Caos"},
  run = function(args)
    local a = advancements.get(SURVIVOR)
    return tr("Chaos Survivor: ", "Superviviente del Caos: ") .. a.progress .. " / " .. a.goal ..
           (a.unlocked and tr(" (unlocked)", " (desbloqueado)") or "")
  end,
}
