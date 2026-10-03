-- Media Player: a desktop app that plays videos and music.
--
-- assets.video opens a clip: an MPEG-1 .mpg file, which the game decodes
-- itself (convert other videos with the ffmpeg command in MODDING.md). A video
-- plays while something draws it, so closing or minimizing the window pauses
-- it by itself. Its sound, and the music track, pause the game's own music
-- while they play.
--
-- The playlist comes from playlist.json (assets.json). Entries whose file is
-- missing are skipped: put your own clips in this folder and list them there.

local function say(en, es) return lang.current() == "es" and es or en end
local function pick(t) return type(t) == "table" and say(t.en or "", t.es or t.en or "") or tostring(t) end

local lcd = assets.font("lcd.bdf")   -- seven-segment digits for the time readout
local list = assets.json("playlist.json")

local clips = {}
for _, entry in ipairs(list.videos) do
  if assets.exists(entry.file) then
    local ok, clip = pcall(assets.video, entry.file)
    -- a clip the system cannot play keeps the reason, shown in its place
    table.insert(clips, {title = pick(entry.title), clip = ok and clip or nil,
                         err = not ok and (tostring(clip):match("assets%.video: (.*)") or tostring(clip)) or nil})
  end
end
local music = assets.music(list.music.file)
music.volume = 0.6
local musicTitle = pick(list.music.title)

local current = 1
local scrubbing = false

-- Layout, in canvas coordinates.
local PAD = 16
local VID = {x = 16, y = 40, w = 448, h = 252}
local BAR_Y = 304
local function barX0() return PAD + 34 end
local function barX1(w) return w - PAD - 204 end
local function inside(x, y, rx, ry, rw, rh) return x >= rx and x <= rx + rw and y >= ry and y <= ry + rh end

local function clock(t)
  t = math.max(0, math.floor(t))
  return string.format("%d:%02d", t // 60, t % 60)
end

local function wrapText(text, x, y, maxW, size, color)
  local line = ""
  for word in text:gmatch("%S+") do
    local try = line == "" and word or (line .. " " .. word)
    if draw.textWidth(try, size) > maxW and line ~= "" then
      draw.text(line, x, y, size, color)
      y = y + size + 4
      line = word
    else
      line = try
    end
  end
  if line ~= "" then draw.text(line, x, y, size, color) end
end

register.app{
  id = "player",
  name = {en = "Media Player", es = "Reproductor"},
  icon = assets.video("icon.mpg"),   -- a silent loop: the icon plays while the desktop shows
  color = "#7de2ff",
  width = 480, height = 330,
  draw = function(w, h, mx, my)
    draw.rect(0, 0, w, h, "#0b1020")
    local item = clips[current]
    draw.text(item and item.title or say("No videos in playlist.json", "No hay videos en playlist.json"),
              PAD, 12, 18, "#e0e8f0")
    if #clips > 1 then
      local hover = inside(mx, my, w - PAD - 56, 8, 56, 22)
      draw.rectLines(w - PAD - 56, 8, 56, 22, hover and "#ffffff" or "#7de2ff", 1)
      draw.text(say("NEXT", "SIG."), w - PAD - 46, 13, 12, "#7de2ff")
    end

    -- The picture, fitted with its aspect kept.
    draw.rect(VID.x - 1, VID.y - 1, VID.w + 2, VID.h + 2, "#1c2638")
    local c = item and item.clip
    if c then
      local s = math.min(VID.w / c.width, VID.h / c.height)
      draw.texture(c, VID.x + VID.w / 2, VID.y + VID.h / 2, {w = c.width * s, h = c.height * s})
    elseif item then
      draw.text(say("This clip cannot play here:", "Este video no se puede reproducir:"),
                VID.x + 12, VID.y + 12, 14, "#ff8a8a")
      wrapText(item.err or "", VID.x + 12, VID.y + 36, VID.w - 24, 12, "#c0c8d4")
    end

    -- Play / pause, the seek bar and the time.
    if c then
      local stopped = c.paused or c.ended
      draw.circle(PAD + 12, BAR_Y + 8, 12, inside(mx, my, PAD, BAR_Y - 4, 24, 24) and "#2a3a52" or "#1c2638")
      if stopped then
        draw.poly(PAD + 13, BAR_Y + 8, 3, 7, 0, "#7dffb0")
      else
        draw.rect(PAD + 7, BAR_Y + 3, 4, 10, "#7dffb0")
        draw.rect(PAD + 14, BAR_Y + 3, 4, 10, "#7dffb0")
      end
      local x0, x1 = barX0(), barX1(w)
      local f = c.duration > 0 and math.min(c.time / c.duration, 1) or 0
      draw.rect(x0, BAR_Y + 5, x1 - x0, 6, "#1c2638")
      draw.rect(x0, BAR_Y + 5, (x1 - x0) * f, 6, "#3fbf9f")
      draw.circle(x0 + (x1 - x0) * f, BAR_Y + 8, 7, "#e8fff2")
      draw.text(clock(c.time) .. "/" .. clock(c.duration), x1 + 14, BAR_Y - 2, 20, "#7dffb0", lcd)
    end

    -- The music track: it takes over the game's music while it plays.
    local mx0 = w - PAD - 64
    local hoverMusic = inside(mx, my, mx0, BAR_Y - 2, 64, 22)
    if music.playing then draw.rect(mx0, BAR_Y - 2, 64, 22, "#3fbf7f") end
    draw.rectLines(mx0, BAR_Y - 2, 64, 22, hoverMusic and "#ffffff" or "#7dffb0", 1)
    draw.text(say("MUSIC", "MÚSICA"), mx0 + 10, BAR_Y + 3, 12, music.playing and "#0b1020" or "#7dffb0")
    if hoverMusic then
      local tw = draw.textWidth(musicTitle, 12)
      draw.rect(w - PAD - tw - 8, BAR_Y - 24, tw + 8, 18, "#1c2638")
      draw.text(musicTitle, w - PAD - tw - 4, BAR_Y - 20, 12, "#e0e8f0")
    end
  end,
  click = function(x, y, button, w, h)
    scrubbing = false
    if #clips > 1 and inside(x, y, w - PAD - 56, 8, 56, 22) then
      current = current % #clips + 1   -- the other clip holds where it was
      return
    end
    if inside(x, y, w - PAD - 64, BAR_Y - 2, 64, 22) then
      if music.playing then music:stop() else music:play() end
      return
    end
    local c = clips[current] and clips[current].clip
    if not c then return end
    if inside(x, y, PAD, BAR_Y - 4, 24, 24) or inside(x, y, VID.x, VID.y, VID.w, VID.h) then
      if c.paused or c.ended then c:play() else c:pause() end
    elseif y >= BAR_Y - 4 and y <= BAR_Y + 20 and x >= barX0() and x <= barX1(w) then
      scrubbing = true
      c:seek((x - barX0()) / (barX1(w) - barX0()) * c.duration)
    end
  end,
  drag = function(x, y, w, h)
    local c = clips[current] and clips[current].clip
    if scrubbing and c then
      local f = math.clamp((x - barX0()) / (barX1(w) - barX0()), 0, 1)
      c:seek(f * c.duration)
    end
  end,
}
