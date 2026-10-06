-- Story Mode: wave mode with a story told through the in-run UI.
--
-- ui.cutscene, ui.dialogue and ui.choose open screens over the run: it holds
-- still while they are up. What the player chose goes in run.data, so a
-- resumed run remembers it (screens themselves are never saved).

local KERNEL = assets.texture("kernel.png")
local RED = "#ff4060"

local function es() return lang.current() == "es" end
local function tr(en, sp) return es() and sp or en end

local MODE = register.gamemode{
  id = "story",
  name = {en = "Story Mode", es = "Modo Historia"},
  description = {
    en = "The KERNEL has noticed you. Choose a blessing, answer its questions, survive.",
    es = "El KERNEL te ha visto. Elige una bendición, responde a sus preguntas, sobrevive.",
  },
  base = "wave",
}

local function active() return run.active and game:isMode(MODE) end

local BLESSINGS = {
  {id = "fury", color = "#ff6040",
   title = {"FURY", "FURIA"}, text = {"+25% damage", "+25% de daño"},
   apply = function(p) p.damage = p.damage * 1.25 end},
  {id = "ward", color = "#60c0ff",
   title = {"WARD", "AMPARO"}, text = {"+3 integrity", "+3 de integridad"},
   apply = function(p) p.maxHp = p.maxHp + 3 p.hp = p.hp + 3 end},
  {id = "haste", color = "#60ff90",
   title = {"HASTE", "PRISA"}, text = {"+15% speed", "+15% de velocidad"},
   apply = function(p) p.speed = p.speed * 1.15 end},
}

local function blessingNamed(id)
  for _, b in ipairs(BLESSINGS) do if b.id == id then return b end end
end

local function say(lines, choices, onChoice, onDone)
  local out = {}
  for i, l in ipairs(lines) do
    out[i] = {speaker = l[1], text = tr(l[2], l[3]),
              portrait = l[1] == "KERNEL" and KERNEL or nil,
              color = l[1] == "KERNEL" and RED or nil}
  end
  return ui.dialogue{lines = out, choices = choices, onChoice = onChoice, onDone = onDone}
end

local function chooseBlessing()
  local options = {}
  for i, b in ipairs(BLESSINGS) do
    options[i] = {title = tr(b.title[1], b.title[2]), description = tr(b.text[1], b.text[2]), color = b.color}
  end
  ui.choose{title = tr("Pick a blessing", "Elige una bendición"), options = options,
    onPick = function(i)
      local b = BLESSINGS[i]
      b.apply(player)
      run.data.blessing = b.id
      ui.toast(tr(b.title[1], b.title[2]) .. tr(" granted", " concedida"))
    end}
end

local function opening()
  ui.cutscene{
    shots = {
      {duration = 2.2, draw = function(t, w, h)
        draw.rect(0, 0, w, h, "#000000")
        local line = tr("SYSTEM BOOT 0x7E3", "ARRANQUE DEL SISTEMA 0x7E3")
        draw.text(line, w / 2 - draw.textWidth(line, 24) / 2, h / 2 - 12, 24,
                  {r = 120, g = 255, b = 160, a = math.floor(math.min(1, t) * 255)})
      end},
      {duration = 2.6, draw = function(t, w, h)
        draw.rect(0, 0, w, h, "#05000a")
        local s = 96 + t * 30
        draw.texture(KERNEL, w / 2, h / 2 - 20, {w = s, h = s})
        local line = tr("Something is watching the process table.", "Algo vigila la tabla de procesos.")
        draw.text(line, w / 2 - draw.textWidth(line, 16) / 2, h / 2 + 70, 16, RED)
      end},
    },
    onDone = function()
      say({{"KERNEL", "You are not supposed to be here.", "No deberías estar aquí."},
           {"YOU", "Then why did you leave the door open?", "¿Entonces por qué dejaste la puerta abierta?"},
           {"KERNEL", "Take a gift. You will need it.", "Toma un regalo. Lo vas a necesitar."}},
          nil, nil, chooseBlessing)
    end,
  }
end

hooks.on("runStart", function(game, resumed)
  if not game:isMode(MODE) then return end
  if resumed then
    if not run.data.blessing then chooseBlessing() end
    return
  end
  run.data = {chapter = 1}
  opening()
end)

hooks.on("waveStart", function(game, wave)
  if not active() or wave ~= 5 or run.data.pact ~= nil then return end
  say({{"KERNEL", "Wave five. You are persistent.", "Oleada cinco. Eres persistente."},
       {"KERNEL", "Join me, and the waves grow gentler. Refuse, and I stop holding back.",
                  "Únete a mí y las oleadas serán más suaves. Niégate y dejaré de contenerme."}},
      {tr("Join", "Unirme"), tr("Refuse", "Negarme")},
      function(i)
        run.data.pact = (i == 1)
        run.data.chapter = 2
        ui.banner(i == 1 and tr("PACT SEALED", "PACTO SELLADO") or tr("DEFIANCE", "DESAFÍO"),
                  i == 1 and tr("Fewer enemies, weaker shots", "Menos enemigos, disparos más débiles")
                         or tr("More enemies, more coins", "Más enemigos, más monedas"), RED, 3)
      end)
end)

-- the pact's consequences
hooks.on("waveEnemyCount", function(count)
  if not active() or run.data.pact == nil then return end
  return run.data.pact and math.floor(count * 0.75) or math.floor(count * 1.3)
end)
hooks.on("bulletHit", function(dmg)
  if active() and run.data.pact == true then return dmg * 0.85 end
end)
hooks.on("coinValue", function(amount)
  if active() and run.data.pact == false then return amount * 2 end
end)

register.hudCard{
  id = "chapter", title = "STORY", color = RED,
  measure = function(w) return active() and 34 or 0 end,   -- 0: hidden outside the mode
  draw = function(x, y, w, h)
    local b = blessingNamed(run.data.blessing or "")
    ui.label(tr("Chapter ", "Capítulo ") .. (run.data.chapter or 1), x, y + 2, {size = 12})
    local line = b and tr(b.title[1], b.title[2]) or tr("no blessing", "sin bendición")
    if run.data.pact ~= nil then
      line = line .. "  ·  " .. (run.data.pact and tr("pact", "pacto") or tr("defiant", "desafiante"))
    end
    ui.label(line, x, y + 18, {size = 10, color = b and b.color or "#a0a0a0"})
  end,
}

register.pauseAction{
  id = "recap", name = {en = "Story so far", es = "La historia hasta ahora"},
  onClick = function(game)
    if not game:isMode(MODE) then
      ui.toast(tr("Not a Story Mode run", "No es una partida del Modo Historia"))
      return
    end
    local b = blessingNamed(run.data.blessing or "")
    ui.toast(tr("Chapter ", "Capítulo ") .. (run.data.chapter or 1) .. ": " ..
             (b and tr(b.title[1], b.title[2]) or "-"))
  end,
}
