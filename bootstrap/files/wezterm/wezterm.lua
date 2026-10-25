-- WezTerm configuration.
--
-- The background is the desktop's: wallpaper-random picks one at session start
-- and records it in $XDG_RUNTIME_DIR/current-wallpaper, and this reads that file
-- when a window is created. No choice of its own, so the terminal and swaybg
-- always show the same image; an open window keeps the one it started with.
--
-- Outside a niri session (no state file) there is no background at all, which is
-- the right failure rather than a second, unrelated image.

local wezterm = require 'wezterm'
local config = wezterm.config_builder()

-- The image swaybg is showing, or nil.
local function desktop_wallpaper()
	local runtime = os.getenv('XDG_RUNTIME_DIR')
	if not runtime then
		return nil
	end
	local file = io.open(runtime .. '/current-wallpaper', 'r')
	if not file then
		return nil
	end
	local path = file:read('*l')
	file:close()
	if not path or path == '' then
		return nil
	end
	return path
end

local background_file = desktop_wallpaper()

config.initial_cols = 80
config.initial_rows = 25

config.font_size = 15
-- Lilex Nerd Font Mono is the machine's monospace default (80-fonts.ts) and
-- comes from ttf-lilex-nerd in extra. The Mono build keeps every glyph, icons
-- included, on the cell grid.
config.font = wezterm.font 'Lilex Nerd Font Mono'
config.color_scheme = 'Dark Pastel'

config.enable_tab_bar = false

config.keys = {
	{ key = 'Backspace', mods = 'CTRL', action = wezterm.action.SendKey { key = 'w', mods= 'CTRL' } },
	{ key = 'Delete', mods = 'CTRL', action = wezterm.action.SendKey { key = 'd', mods= 'ALT' } }
}

-- $HOME so it does not depend on which account name is in .env. With no images
-- there is no background at all, which is the right failure on a machine whose
-- wallpapers have not been supplied yet.
if background_file then
	config.background = {
		{
			source = { File = background_file },
			height = "Cover",
			width = "Cover",
			vertical_align = "Middle",
			horizontal_align = "Center",
			repeat_x = "NoRepeat",
			repeat_y = "NoRepeat",
			hsb = {
				brightness = 0.15,
				saturation = 0.9
			}
		}
	}
end

return config
