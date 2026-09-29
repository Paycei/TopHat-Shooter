-- Neon Pack: cosmetics. Nothing here changes how the game plays; equip them
-- in MODS.EXE > Cosmetics (they are remembered for this profile).

register.cosmetic{
  kind = "player", id = "neon_pulse",
  name = {en = "Neon Pulse", es = "Pulso de Neón"},
  description = {en = "Magenta body, cyan trim.", es = "Cuerpo magenta, bordes cian."},
  colors = {"#ff2bd6", "#2bf0ff", "#ffffff"},   -- body, trim, core
}

register.cosmetic{
  kind = "player", id = "neon_core",
  name = {en = "Neon Core", es = "Núcleo de Neón"},
  description = {en = "An animated GIF: two sparks orbit a pulsing core.",
                 es = "Un GIF animado: dos chispas orbitan un núcleo que late."},
  texture = "neon_core.gif",   -- a GIF plays by itself, at the speed saved in it
  scale = 1.4, rotate = true,  -- a bit bigger; the nose turns to where you move
}

register.cosmetic{
  kind = "bullet", id = "neon_trail",
  name = {en = "Neon Trail", es = "Estela de Neón"},
  colors = {"#2bf0ff", "#ff2bd6", "#7a3cff"},   -- body, glow, trail
}

register.cosmetic{
  kind = "desktop", id = "neon_grid",
  name = {en = "Neon Grid", es = "Rejilla de Neón"},
  texture = "wallpaper.png",   -- scaled from the screen's top-left corner
  cube = true,   -- keep the desktop cube floating over the wallpaper
}
