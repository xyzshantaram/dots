-- WezTerm configuration.
--
-- The background comes out of ~/wallpapers, the same directory 112-wallpaper.ts
-- populates and swaybg picks from at random. Nothing here is committed: the
-- repo ships the mechanism, the images are yours. See files/wallpapers/README.md.
--
-- One image per day: the day of the year picks an entry from the sorted
-- directory, so the choice changes every 24 hours with no daemon and no state
-- file. WezTerm reads the background when a window is created, so an open
-- window keeps the image it started with and the next one gets today's.

local wezterm = require 'wezterm'
local config = wezterm.config_builder()

-- The wallpapers directory, indexed by the day of the year.
local function today_wallpaper()
	local dir = os.getenv('HOME') .. '/wallpapers'
	local files = {}
	for _, pattern in ipairs { '*.png', '*.jpg', '*.jpeg', '*.webp' } do
		for _, path in ipairs(wezterm.glob(dir .. '/' .. pattern) or {}) do
			table.insert(files, path)
		end
	end
	if #files == 0 then
		return nil
	end
	table.sort(files)
	local day = tonumber(os.date('%j')) or 1
	return files[(day % #files) + 1]
end

local background_file = today_wallpaper()

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
