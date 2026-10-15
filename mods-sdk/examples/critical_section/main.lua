-- Critical Section: a PvP mode (king of the hill).
--
-- The host picks it in PVP.EXE's Mode row. Every machine in the lobby runs
-- this script (a lobby needs the same mods), but only the host decides the
-- match, so:
--   * the rules (scoring, the section, the shots, the blink) run on the host,
--     in hooks that only fire there (pvpUpdate, pvpShoot, pvpRequest, ...);
--   * match.data is the host's table, copied to every machine: the section
--     and the scores live there, so every client can draw them;
--   * a player asks the host for something with match:request, and the host
--     tells everyone with match:broadcast.

local MODE = register.pvpmode{
  id = "critical_section",
  name = {en = "Critical Section", es = "Sección Crítica"},
  description = {
    en = "Hold the critical section alone to score: two processes inside and nobody does. "
      .. "30 seconds wins. Inside, your shots are privileged. Blink with F.",
    es = "Ocupa la sección crítica a solas para puntuar: con dos procesos dentro nadie puntúa. "
      .. "30 segundos ganan. Dentro, tus disparos son privilegiados. Salta con F.",
  },
  -- Lobby presets (the host can still change them). Kills never end it.
  settings = {killLimit = false, timeLimit = 240, respawn = 2},
}

local GOAL = 30           -- seconds of holding to win
local MOVE_EVERY = 35     -- the section moves this often
local BLINK = 170         -- blink distance
local BLINK_COOLDOWN = 8
local ROOT = "critical_section:root"   -- our bullets' kind

register.keybind{
  id = "blink",
  name = {en = "Blink (Critical Section)", es = "Salto (Sección Crítica)"},
  default = "f",
  gamepad = "RightFaceUp",
}

local function on(match) return match:isMode(MODE) end

local function es() return lang.current() == "es" end

-- Who a score belongs to: the team in team matches, else the player.
local function side(match, p)
  if match.teams then return p.teamId end
  return "p" .. p.index
end

-- That side as match:finish takes it: a team name, or the player.
local function winnerOf(match, who)
  if match.teams then return who end
  return match:player(tonumber(who:sub(2)))
end

local function inside(z, p)
  return p.alive and (p.x - z.x) ^ 2 + (p.y - z.y) ^ 2 <= z.r ^ 2
end

local SPOTS = {{0.5, 0.5}, {0.27, 0.3}, {0.73, 0.7}, {0.27, 0.7}, {0.73, 0.3}}

local function moveSection(match)
  local spot = SPOTS[math.random(#SPOTS)]
  match.data.zone = {x = match.width * spot[1], y = match.height * spot[2], r = 90,
                     moveAt = match.time + MOVE_EVERY}
end

-- ---------------------------------------------------------------- host ----
-- pvpStart fires on every machine; the host sets the match up and its
-- match.data reaches the clients with the start signal.
hooks.on("pvpStart", function(match)
  if not on(match) or not match.isHost then return end
  match.data.score = {}
  match.data.cooldown = {}
  moveSection(match)
end)

hooks.on("pvpUpdate", function(match, dt)
  if not on(match) then return end
  local d = match.data
  if match.time >= d.zone.moveAt then moveSection(match) end
  -- exactly one side inside scores; two sides inside is "contested"
  local who, contested = nil, false
  for p in match:players() do
    if inside(d.zone, p) then
      local s = side(match, p)
      if who and who ~= s then contested = true end
      who = who or s
    end
  end
  if contested then who = nil end
  d.holder, d.contested = who, contested
  if who then
    d.score[who] = (d.score[who] or 0) + dt
    if d.score[who] >= GOAL then
      match:finish(winnerOf(match, who), {en = "held the critical section for 30 seconds",
                                          es = "ocupó la sección crítica 30 segundos"})
    end
  end
end)

-- The match only ends by our rules: at time up, the longest holder wins.
hooks.on("pvpEnding", function(match, reason)
  if not on(match) then return end
  if reason == "time" then
    local best, bestScore, tie = nil, -1, false
    for who, s in pairs(match.data.score) do
      if s > bestScore then best, bestScore, tie = who, s, false
      elseif s == bestScore then tie = true end
    end
    match:finish(best and not tie and winnerOf(match, best) or nil,
                 {en = "time up: the longest holder wins", es = "tiempo: gana quien más la ocupó"})
  end
  return true   -- (kills and eliminations never end it)
end)

-- Inside an uncontested section, a shot is a privileged round: bigger, faster
-- and it goes through one player. Returning true replaces the normal shot.
hooks.on("pvpShoot", function(match, p, dx, dy)
  if not on(match) or match.data.contested or not inside(match.data.zone, p) then return end
  local speed = p.bulletSpeed * 1.25
  match:spawnBullet{owner = p, x = p.x + dx * 24, y = p.y + dy * 24, vx = dx * speed, vy = dy * speed,
                    radius = 11, color = "#ffb020", kind = ROOT, pierce = 1}
  return true
end)

-- A player's blink request (see pvpFrame below): the host checks it and moves them.
hooks.on("pvpRequest", function(match, p, name, data)
  if not on(match) or name ~= "critical_section:blink" or not p.alive then return end
  -- A request is another machine's word: check it before trusting it.
  if type(data) ~= "table" or type(data.x) ~= "number" or type(data.y) ~= "number" then return end
  local d = match.data
  local key = "p" .. p.index
  if (d.cooldown[key] or 0) > match.time then return end   -- still recharging
  local dx, dy = data.x - p.x, data.y - p.y
  local len = math.sqrt(dx * dx + dy * dy)
  if len < 1 then return end
  local step = math.min(len, BLINK)
  local fromX, fromY = p.x, p.y
  match:teleport(p, p.x + dx / len * step, p.y + dy / len * step)
  d.cooldown[key] = match.time + BLINK_COOLDOWN
  match:broadcast("critical_section:blinked", {x1 = fromX, y1 = fromY, x2 = p.x, y2 = p.y})
end)

-- --------------------------------------------------------- every machine ----
-- Each machine reads its own player's keys and asks the host.
hooks.on("pvpFrame", function(match)
  if not on(match) or not match.localPlayer.alive then return end
  if input.bindPressed("blink") then
    local x, y = input.mouse()
    match:request("critical_section:blink", {x = x, y = y})
  end
end)

hooks.on("pvpBroadcast", function(match, name, data)
  if name ~= "critical_section:blinked" then return end
  match:particles(data.x1, data.y1, "#64d8ff", 14)
  match:particles(data.x2, data.y2, "#64d8ff", 24)
end)

hooks.on("pvpKill", function(match, victim, killer)
  local z = on(match) and match.data.zone
  if z and killer and killer.isLocal and (victim.x - z.x) ^ 2 + (victim.y - z.y) ^ 2 <= z.r ^ 2 then
    match:toast({en = "Evicted from the critical section!", es = "¡Expulsado de la sección crítica!"}, "#ffb020")
  end
end)

hooks.on("pvpBulletDraw", function(b)
  if b.kind ~= ROOT then return end
  draw.circle(b.x, b.y, b.radius + 5, "#ffb02040")
  draw.circle(b.x, b.y, b.radius, "#ffb020")
  draw.circleLines(b.x, b.y, b.radius + 5, "#fff2c0", 1.5)
  return true
end)

hooks.on("pvpDrawBackground", function(match)
  local z = on(match) and match.data.zone
  if not z then return end   -- (a client before the host's first copy arrives)
  local d = match.data
  local col = d.contested and "#ff5a5a" or (d.holder and "#ffb020" or "#64d8ff")
  draw.circle(z.x, z.y, z.r, col .. "26")
  draw.circleLines(z.x, z.y, z.r, col, 3)
  -- the time until it moves, as a shrinking ring
  local left = math.max(0, z.moveAt - match.time) / MOVE_EVERY
  if left > 0 then draw.circleLines(z.x, z.y, z.r * left, col .. "70", 1.5) end
  local label = es() and "SECCIÓN CRÍTICA" or "CRITICAL SECTION"
  draw.text(label, z.x - draw.textWidth(label, 12) / 2, z.y - z.r - 18, 12, col)
end)

hooks.on("pvpDrawHud", function(match, w, h)
  local d = on(match) and match.data
  if not d or not d.score then return end
  -- one bar per side, top left
  local rows = {}
  if match.teams then
    local seen = {}
    for p in match:players() do
      if not seen[p.teamId] then
        seen[p.teamId] = true
        rows[#rows + 1] = {key = p.teamId, name = lang.text("pvp_team_" .. p.teamId:sub(3):lower()),
                           mine = p.teamId == match.localPlayer.teamId}
      end
    end
  else
    for p in match:players() do
      rows[#rows + 1] = {key = "p" .. p.index, name = p.name, mine = p.isLocal}
    end
  end
  local x, y = 12, 40
  draw.rect(x - 6, y - 6, 204, #rows * 22 + 8, "#0a0e18cc")
  for i, row in ipairs(rows) do
    local s = d.score[row.key] or 0
    local yy = y + (i - 1) * 22
    draw.text(row.name .. "  " .. math.floor(s) .. "/" .. GOAL, x, yy, 12, row.mine and "#ffffff" or "#a8b0c0")
    draw.rect(x, yy + 14, 190, 3, "#ffffff22")
    draw.rect(x, yy + 14, 190 * math.min(1, s / GOAL), 3, row.key == d.holder and "#ffb020" or "#64d8ff")
  end
  -- this machine's blink
  local cd = d.cooldown and d.cooldown["p" .. match.localPlayer.index]
  local ready = not cd or cd <= match.time
  local text = (es() and "SALTO " or "BLINK ") .. (ready and (es() and "LISTO" or "READY")
                                                    or tostring(math.ceil(cd - match.time)))
  draw.text(text, w - draw.textWidth(text, 14) - 14, h - 32, 14, ready and "#64d8ff" or "#7a8496")
end)
