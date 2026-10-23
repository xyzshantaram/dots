-- WezTerm configuration.
--
-- The background comes out of ~/wallpapers, the same directory 112-wallpaper.ts
-- populates and swaybg picks from at random. Nothing here is committed: the
-- repo ships the mechanism, the images are yours. See files/wallpapers/README.md.
--
-- Change the name below to use a different image. If the file is absent wezterm
-- logs a warning and starts with a plain background, so a fresh machine without
-- wallpapers still works.

local background_file = 'Drangarnir.png'

local wezterm = require 'wezterm'
local config = wezterm.config_builder()

config.initial_cols = 80
config.initial_rows = 25

config.font_size = 15
-- Nerd Fonts 3.x calls this family "FantasqueSansM Nerd Font Mono". The bare
-- "FantasqueSansMono Nerd Font" does not exist, and asking for it makes
-- fontconfig substitute a default without any error.
config.font = wezterm.font 'FantasqueSansM Nerd Font Mono'
config.color_scheme = 'Dark Pastel'

config.enable_tab_bar = false

config.keys = {
	{ key = 'Backspace', mods = 'CTRL', action = wezterm.action.SendKey { key = 'w', mods= 'CTRL' } },
	{ key = 'Delete', mods = 'CTRL', action = wezterm.action.SendKey { key = 'd', mods= 'ALT' } }
}

-- $HOME so it does not depend on which account name is in .env.
config.background = {
  {
    source = {
      File = os.getenv('HOME') .. '/wallpapers/' .. background_file,
    },
    height = "Cover",
    width = "Cover",
    vertical_align = "Middle",
    horizontal_align = "Center",
    repeat_x = "NoRepeat",
    repeat_y = "NoRepeat",
    hsb = {
    	brightness = 0.4,
    	saturation = 0.9
    }
  }
}

return config
