-- Neon Pack: cosmetics. Nothing here changes how the game plays; equip them
-- in MODS.EXE > Cosmetics (they are remembered for this profile).

register.cosmetic{
  kind = "player", id = "neon_pulse",
  name = {en = "Neon Pulse", es = "Pulso de Neón"},
  description = {en = "Magenta body, cyan trim.", es = "Cuerpo magenta, bordes cian."},
  colors = {"#ff2bd6", "#2bf0ff", "#ffffff"},   -- body, trim, core
}

register.cosmetic{
  kind = "bullet", id = "neon_trail",
  name = {en = "Neon Trail", es = "Estela de Neón"},
  colors = {"#2bf0ff", "#ff2bd6", "#7a3cff"},   -- body, glow, trail
}

register.cosmetic{
  kind = "desktop", id = "neon_grid",
  name = {en = "Neon Grid", es = "Rejilla de Neón"},
  texture = "wallpaper.png",
  -- cube = true,   -- keep the desktop cube floating over the wallpaper
}
