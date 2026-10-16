-- The game-shipped screens of the `ui` library: ui.dialogue, ui.choose and
-- ui.cutscene. Plain Lua on top of ui.open and the widgets, loaded once into
-- the shared library table (mod_ui.nim); each runs as the mod that calls it.

local function confirmPressed()
  return input.pressed("space") or input.pressed("enter")
end

local function wrap(text, width, size)
  local lines, line = {}, ""
  for para in (text .. "\n"):gmatch("(.-)\n") do
    line = ""
    for word in para:gmatch("%S+") do
      local cand = (line == "") and word or (line .. " " .. word)
      if line ~= "" and draw.textWidth(cand, size) > width then
        lines[#lines + 1] = line
        line = word
      else
        line = cand
      end
    end
    lines[#lines + 1] = line
  end
  return lines
end

-- ui.dialogue{lines = {{speaker =, text =, portrait = texture, color =}, ...},
--   choices = {"Yes", "No"}, onChoice = fn(i), onDone = fn(), speed = 45,
--   pause = true, skippable = true}
function ui.dialogue(opts)
  local lines = opts.lines or {}
  if #lines == 0 then error("ui.dialogue needs lines = {{speaker = .., text = ..}, ...}", 2) end
  local i, t, done = 1, 0, false
  local speed = opts.speed or 45
  local handle
  local function cur() return lines[i] end
  local function fullyShown() return t * speed >= #(cur().text or "") end
  local function finish(choice)
    if done then return end
    done = true
    if choice and opts.onChoice then opts.onChoice(choice) end
    if opts.onDone then opts.onDone() end
    handle:close()
  end
  local function advance()
    if not fullyShown() then t = 1e9 return end
    if i == #lines and opts.choices then return end   -- a choice closes it
    if i < #lines then i, t = i + 1, 0 else finish() end
  end
  handle = ui.open{
    pause = opts.pause ~= false, closeOnBack = opts.skippable ~= false,
    update = function(dt)
      t = t + dt
      if confirmPressed() then advance() end
    end,
    click = function() advance() end,
    onClose = function() if not done then done = true if opts.onDone then opts.onDone() end end end,
    draw = function(w, h)
      local line = cur()
      local bw = math.min(w - 40, 760)
      local bx, bh = (w - bw) / 2, 150
      local by = h - bh - 30
      local col = line.color or "#00c8ff"
      ui.panel(bx, by, bw, bh, {color = col, title = line.speaker})
      local tx = bx + 16
      if line.portrait then
        draw.texture(line.portrait, bx + 16, by + 26, {w = 96, h = 96, origin = "topleft"})
        tx = bx + 124
      end
      local shown = string.sub(line.text or "", 1, math.floor(t * speed))
      local ty = by + 28
      for _, l in ipairs(wrap(shown, bx + bw - 16 - tx, 16)) do
        draw.text(l, tx, ty, 16, "#e4f0fa")
        ty = ty + 20
      end
      if i == #lines and opts.choices and fullyShown() then
        local n = #opts.choices
        local cw = math.min(180, (bw - 32 - (n - 1) * 8) / n)
        for k, label in ipairs(opts.choices) do
          if ui.button(bx + bw - 16 - (n - k + 1) * (cw + 8) + 8, by + bh - 40, cw, 28, label, {color = col}) then
            finish(k)
          end
        end
        for k = 1, math.min(n, 9) do
          if input.pressed(tostring(k)) then finish(k) end
        end
      elseif fullyShown() then
        draw.text(i < #lines and "[SPACE] >" or "[SPACE] OK", bx + bw - 90, by + bh - 22, 12, col)
      end
    end,
  }
  return handle
end

-- ui.choose{title =, options = {{title =, description =, icon = texture, color =}, ...},
--   onPick = fn(i), allowSkip = false, pause = true}
function ui.choose(opts)
  local options = opts.options or {}
  if #options == 0 then error("ui.choose needs options = {{title = ..}, ...}", 2) end
  local sel, done = 1, false
  local handle
  local function pick(k)
    if done then return end
    done = true
    handle:close()
    if opts.onPick then opts.onPick(k) end
  end
  handle = ui.open{
    pause = opts.pause ~= false, closeOnBack = opts.allowSkip == true,
    onClose = function() if not done then done = true if opts.onPick then opts.onPick(nil) end end end,
    update = function()
      if input.pressed("left") or input.pressed("a") then sel = math.max(1, sel - 1) end
      if input.pressed("right") or input.pressed("d") then sel = math.min(#options, sel + 1) end
      if confirmPressed() then pick(sel) end
    end,
    draw = function(w, h)
      draw.rect(0, 0, w, h, {0, 0, 0, 150})
      if opts.title then
        draw.text(opts.title, (w - draw.textWidth(opts.title, 28)) / 2, h * 0.18, 28, "#e4f0fa")
      end
      local n = #options
      local cw = math.min(220, (w - 80 - (n - 1) * 20) / n)
      local ch = 260
      local x0 = (w - (n * cw + (n - 1) * 20)) / 2
      local y0 = (h - ch) / 2
      for k, o in ipairs(options) do
        local x = x0 + (k - 1) * (cw + 20)
        local col = o.color or "#00c8ff"
        local px, py = ui.pointer()
        if px >= x and px < x + cw and py >= y0 and py < y0 + ch then sel = k end
        ui.panel(x, y0, cw, ch, {color = col, title = (k == sel) and "> SELECT" or " "})
        if k == sel then draw.rectLines(x - 3, y0 - 3, cw + 6, ch + 6, col, 2) end
        local ty = y0 + 28
        if o.icon then
          draw.texture(o.icon, x + cw / 2, ty + 36, {w = 64, h = 64})
          ty = ty + 80
        end
        ty = ty + ui.label(o.title or "", x + 10, ty, {size = 18, width = cw - 20, align = "center"})
        ui.label(o.description or "", x + 10, ty + 6, {size = 12, width = cw - 20, color = "#9fb4c8"})
        if ui.button(x + 10, y0 + ch - 38, cw - 20, 28, "CHOOSE", {color = col}) then pick(k) end
      end
      if opts.allowSkip then
        draw.text("[ESC] skip", (w - draw.textWidth("[ESC] skip", 12)) / 2, y0 + ch + 20, 12, "#87a0b6")
      end
    end,
  }
  return handle
end

-- ui.cutscene{shots = {{duration = 2, draw = fn(t, w, h)}, ...}, skippable = true,
--   onDone = fn()} -- full screen, over everything; confirm skips a shot
function ui.cutscene(opts)
  local shots = opts.shots or {}
  if #shots == 0 then error("ui.cutscene needs shots = {{duration = .., draw = fn(t, w, h)}, ...}", 2) end
  local i, t, done = 1, 0, false
  local handle
  local function finish()
    if done then return end
    done = true
    handle:close()
    if opts.onDone then opts.onDone() end
  end
  local function nextShot()
    if i < #shots then i, t = i + 1, 0 else finish() end
  end
  handle = ui.open{
    layer = "screen", pause = true, closeOnBack = opts.skippable ~= false,
    onClose = function() if not done then done = true if opts.onDone then opts.onDone() end end end,
    update = function(dt)
      t = t + dt
      if t >= (shots[i].duration or 2) then nextShot() end
      if opts.skippable ~= false and confirmPressed() then nextShot() end
    end,
    click = function() if opts.skippable ~= false then nextShot() end end,
    draw = function(w, h)
      draw.rect(0, 0, w, h, "#000000")
      if not done and shots[i].draw then shots[i].draw(t, w, h) end
    end,
  }
  return handle
end
