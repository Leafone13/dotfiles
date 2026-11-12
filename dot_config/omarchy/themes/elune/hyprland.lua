-- Elune: border values copied from colors.toml (hyprland_*_border): this file wins, keep both in sync.
-- The violet-teal gradient slowly turns (no shadow halo: it drowned the gradient).
local active_border_color = { colors = { "rgba(b8a7ffee)", "rgba(8ed9e8ee)" }, angle = 45 }
local inactive_border_color = "rgba(2d2950aa)"

hl.config({
  general = {
    col = {
      active_border = active_border_color,
      inactive_border = inactive_border_color,
    },
  },

  group = {
    col = {
      border_active = active_border_color,
      border_inactive = inactive_border_color,
    },
  },
})

-- one turn ~5 s; runs all the time, so a little extra redraw on battery
hl.animation({ leaf = "borderangle", enabled = true, speed = 50, bezier = "linear", style = "loop" })
