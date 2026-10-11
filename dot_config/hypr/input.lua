-- Keep only your personal input overrides here. Uncommented settings below
-- replace Omarchy's defaults.

-- Keyboard layout and options.
-- See https://wiki.hypr.land/Configuring/Basics/Variables/#input
-- hl.config({
--   input = {
--     -- Use multiple keyboard layouts and switch between them with Left Alt + Right Alt.
--     kb_layout = "us,dk,eu",
--     kb_options = "compose:caps,shift:both_capslock_cancel,grp:alts_toggle",
--
--     -- Use a specific keyboard variant if needed (e.g. intl for international keyboards).
--     kb_variant = "intl",
--
--     -- Change speed of keyboard repeat.
--     repeat_rate = 40,
--     repeat_delay = 250,
--
--     -- Start with numlock on by default.
--     numlock_by_default = true,
--
--     -- Increase sensitivity for mouse/trackpad (default: 0).
--     sensitivity = 0.35,
--
--     -- Turn off mouse acceleration (default: adaptive).
--     accel_profile = "flat",
--
--     touchpad = {
--       -- Use natural (inverse) scrolling.
--       natural_scroll = true,
--
--       -- Use two-finger clicks for right-click instead of lower-right corner.
--       clickfinger_behavior = true,
--
--       -- Control the speed of your scrolling.
--       scroll_factor = 0.4,
--
--       -- Enable the touchpad while typing.
--       disable_while_typing = false,
--
--       -- Left-click-and-drag with three fingers.
--       drag_3fg = 1,
--     },
--   },
-- })

-- App-specific touchpad scroll speeds.
-- o.window("(Alacritty|kitty|foot)", { scroll_touchpad = 1.5 })
-- o.window("com.mitchellh.ghostty", { scroll_touchpad = 0.2 })

-- Enable touchpad gestures for changing workspaces.
-- See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Gestures/
hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })

-- Three-finger swipe up/down opens/closes the hyprexpo workspace overview.
-- Falls back to the workspace list when the plugin isn't loaded
-- (e.g. after a Hyprland update, until `hyprpm update` is run).
local hyprexpo_loaded = false
for _, plugin in ipairs(hl.get_loaded_plugins()) do
  if plugin.name == "hyprexpo" then hyprexpo_loaded = true end
end

if hyprexpo_loaded then
  hl.config({
    plugin = {
      hyprexpo = {
        columns = 3,
        gaps_in = 8,
        gaps_out = 16,
        -- Show only workspaces that exist (have windows), sized to fit.
        dynamic_grid = 1,
        fill_gaps = 0,
        mru_sort = 0,
        skip_empty = 1,
        wallpaper_bg = 1,
        show_workspace_names = 1,
        label_position = "top-left",
        label_size = 28,
      },
    },
  })
  hl.plugin.hyprexpo.gesture({ fingers = 3, direction = "up", action = "expo" })
  -- Swiping down closes the overview and switches to the hovered workspace.
  hl.plugin.hyprexpo.gesture({ fingers = 3, direction = "down", action = "expo" })
else
  hl.gesture({ fingers = 3, direction = "up", action = function() hl.exec_cmd(os.getenv("HOME") .. "/.local/bin/workspace-picker") end })
end

-- Enable touchpad gestures for moving focus (helpful on scrolling layout).
-- hl.gesture({ fingers = 3, direction = "left", action = function() hl.dispatch(hl.dsp.focus({ direction = "l" })) end })
-- hl.gesture({ fingers = 3, direction = "right", action = function() hl.dispatch(hl.dsp.focus({ direction = "r" })) end })

-- English + Russian, switch with Left Alt + Right Alt.
hl.config({
  input = {
    kb_layout = "us,ru",
    kb_options = "compose:caps,shift:both_capslock_cancel,grp:alts_toggle",

    -- Natural (inverse) scrolling, like on the previous Arch setup.
    touchpad = {
      natural_scroll = true,
      clickfinger_behavior = true,
      scroll_factor = 0.4,
    },
  },
})
