-- A module of the mod's own: main.lua loads it with require("util").
-- (Another mod's module is require("<its id>:<module>"), once that mod has
-- loaded: list it in your mod.json "dependencies" or "loadAfter".)

local util = {}

-- Read a whole file, or nil if it is not there.
function util.readFile(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local text = f:read("a")
  f:close()
  return text
end

function util.writeFile(path, text)
  local f = assert(io.open(path, "w"))
  f:write(text)
  f:close()
end

return util
