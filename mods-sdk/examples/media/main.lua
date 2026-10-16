-- Media: videos, pictures and music, in two parts.
--
-- * This file: a Media Player app on the desktop.
-- * plaza.lua: Billboard Plaza, a 3D game mode with videos and pictures on
--   screens and billboards. require runs another file of your mod folder.
--
-- assets.video opens an MPEG-1 .mpg clip, which the game decodes itself
-- (convert other videos with the ffmpeg command in MODDING.md). A video plays
-- while something draws it, so closing or minimizing the window pauses it by
-- itself. Its sound, and the music track, pause the game's own music while
-- they play.

require("plaza")

local function say(en, es) return lang.current() == "es" and es or en end

-- The playlist comes from playlist.json: put your own clips in this folder
-- and list them there. A missing file is skipped.
local list = assets.json("playlist.json")
local clips = {}
for _, entry in ipairs(list.videos) do
  if assets.exists(entry.file) then
    local ok, clip = pcall(assets.video, entry.file)
    if ok then
      clips[#clips + 1] = {title = entry.title, video = clip}
    else
      mod.warn(clip)   -- not an MPEG-1 file: the message gives the ffmpeg command
    end
  end
end
local music = assets.music(list.music.file)
music.volume = 0.6
local lcd = assets.font("lcd.bdf")   -- seven-segment digits for the time readout
local current = 1

-- Layout, in canvas coordinates (the canvas is the app's width x height).
local VID = {x = 16, y = 40, w = 448, h = 252}   -- the picture; click it to play or pause
local BAR = {x = 16, y = 300, w = 240, h = 24}   -- the seek bar; click or drag it
local NEXT = {x = 396, y = 8, w = 68, h = 22}
local MUSIC = {x = 400, y = 302, w = 64, h = 22}

local function inside(x, y, r) return x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h end
local function clock(t)
  t = math.floor(t)
  return string.format("%d:%02d", t // 60, t % 60)
end
local function seek(c, x) c:seek(math.clamp((x - BAR.x) / BAR.w, 0, 1) * c.duration) end

register.app{
  id = "player",
  name = {en = "Media Player", es = "Reproductor"},
  icon = assets.video("icon.mpg"),   -- a silent loop: the icon plays while the desktop shows
  color = "#7de2ff",
  width = 480, height = 330,
  draw = function(w, h, mx, my)
    draw.rect(0, 0, w, h, "#0b1020")
    -- The music track: it takes over the game's music while it plays.
    if music.playing then draw.rect(MUSIC.x, MUSIC.y, MUSIC.w, MUSIC.h, "#3fbf7f") end
    draw.rectLines(MUSIC.x, MUSIC.y, MUSIC.w, MUSIC.h, "#7dffb0", 1)
    draw.text(say("MUSIC", "MÚSICA"), MUSIC.x + 10, MUSIC.y + 5, 12, music.playing and "#0b1020" or "#7dffb0")

    local item = clips[current]
    if not item then
      draw.text(say("No videos in playlist.json", "No hay videos en playlist.json"), 16, 12, 18, "#e0e8f0")
      return
    end
    local c = item.video
    draw.text(say(item.title.en, item.title.es), 16, 12, 18, "#e0e8f0")
    if #clips > 1 then draw.text(say("NEXT >", "SIG. >"), NEXT.x + 8, NEXT.y + 5, 14, "#7de2ff") end

    -- The picture, fitted with its aspect kept.
    draw.rect(VID.x, VID.y, VID.w, VID.h, "#1c2638")
    local s = math.min(VID.w / c.width, VID.h / c.height)
    draw.texture(c, VID.x + VID.w / 2, VID.y + VID.h / 2, {w = c.width * s, h = c.height * s})
    if c.paused then draw.text(say("PAUSED", "EN PAUSA"), VID.x + 8, VID.y + 8, 14, "#7dffb0") end

    -- The seek bar, and the time in the LCD font.
    local f = c.duration > 0 and c.time / c.duration or 0
    draw.rect(BAR.x, BAR.y + 9, BAR.w, 6, "#1c2638")
    draw.rect(BAR.x, BAR.y + 9, BAR.w * f, 6, "#3fbf9f")
    draw.circle(BAR.x + BAR.w * f, BAR.y + 12, 7, "#e8fff2")
    draw.text(clock(c.time) .. "/" .. clock(c.duration), BAR.x + BAR.w + 14, BAR.y + 2, 20, "#7dffb0", lcd)
  end,
  click = function(x, y, button, w, h)
    if inside(x, y, MUSIC) then
      if music.playing then
        music:stop()
      else
        music:play()
        ui.toast(say(list.music.title.en, list.music.title.es))
      end
      return
    end
    local item = clips[current]
    if not item then return end
    if #clips > 1 and inside(x, y, NEXT) then
      current = current % #clips + 1   -- the other clip holds where it was
    elseif inside(x, y, VID) then
      if item.video.paused then item.video:play() else item.video:pause() end
    elseif inside(x, y, BAR) then
      seek(item.video, x)
    end
  end,
  drag = function(x, y, w, h)
    local item = clips[current]
    if item and inside(x, y, BAR) then seek(item.video, x) end
  end,
}
