-- Keybind Demo
-- Change these in Settings > Controls > Mod Keybinds, then use them during a run.
local ping = register.keybind{
  id = "ping",
  name = {en = "Ping", es = "Marcar"},
  default = "f6",
  gamepad = "RightFaceUp"
}

local clear = register.keybind{
  id = "clear",
  name = {en = "Clear message", es = "Borrar mensaje"},
  default = "f7",
  gamepad = "RightFaceLeft"
}

local message = "F6 pings the HUD"
local messageTime = 0

hooks.on("update", function(game, dt)
  messageTime = math.max(0, messageTime - dt)
  if input.bindPressed("ping") then
    message = "PING!"
    messageTime = 2
  end
  if input.bindPressed("clear") then
    message = ""
    messageTime = 0
  end
end)

hooks.on("drawHud", function(game, width, height)
  local ax, ay = draw.arena()
  local x, y = ax + 16, ay + 16
  local color = messageTime > 0 and "#64d8ff" or "#a8b4c8"
  draw.rect(x - 10, y - 8, 250, 58, "#101824dd")
  draw.rectLines(x - 10, y - 8, 250, 58, "#4d7999", 1)
  draw.text(message, x, y, 18, color)
  draw.text("F6 ping / F7 clear", x, y + 25, 13, "#b0b8c8")
end)
