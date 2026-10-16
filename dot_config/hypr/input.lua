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

-- Mac-style four-finger pinch (thumb + three fingers), live like macOS:
-- the Launchpad (logos.launchpad shell plugin) follows the fingers while they
-- move, commits past ~a third, and cancels if you spread back. Spreading while
-- it is open closes it; spreading while it is closed shows the desktop.
-- Progress goes through a tiny file in XDG_RUNTIME_DIR that the plugin watches.
local lp_dir = os.getenv("XDG_RUNTIME_DIR") or "/tmp"
local lp_gesture_file = lp_dir .. "/omarchy-launchpad-gesture"
local lp_state_file = lp_dir .. "/omarchy-launchpad-open"

local function lp_write(line)
  local f = io.open(lp_gesture_file, "w")
  if f then f:write(line, "\n"); f:close() end
end

local function lp_is_open()
  local f = io.open(lp_state_file, "r")
  if not f then return false end
  local v = f:read("*l")
  f:close()
  return v == "1"
end

local function lp_clamp(v) return math.max(0, math.min(1, v)) end

-- Tuned from recorded pinches on this touchpad: Hyprland starts the gesture at
-- scale ~0.89 (its 10% dead zone), a full pinch ends around 0.3-0.65, and
-- updates arrive every ~7 ms. Every update is written; QML coalesces per frame.
-- Release follows WWDC18 "Designing Fluid Interfaces" / GNOME's swipeTracker:
-- velocity over the last 150 ms, decide on the projected position, and pass the
-- velocity on so the finish animation leaves at the speed the fingers had.
local LP_START = 0.89       -- scale of the first event (Hyprland's dead zone)
local LP_FULL = 0.45        -- scale at which the Launchpad is fully shown
local LP_FULL_SPREAD = 1.6  -- scale at which an open Launchpad is fully gone
local LP_PROJECT_MS = 200   -- how far ahead the release decision looks
local LP_VELOCITY_MS = 150  -- window for the release velocity

local lp = { open = false, scale = 1, progress = 0, samples = {} }

local function lp_velocity()
  local n = #lp.samples
  if n < 2 then return 0 end
  local last = lp.samples[n]
  local first = last
  for i = n, 1, -1 do
    if last.t - lp.samples[i].t > LP_VELOCITY_MS then break end
    first = lp.samples[i]
  end
  local dt = last.t - first.t
  if dt <= 0 then return 0 end
  return (last.p - first.p) / dt
end

local lp_action = {
  start = function(e)
    lp.open = lp_is_open()
    lp.scale = 1
    lp.progress = lp.open and 1 or 0
    lp.samples = { { t = e.time_ms, p = lp.progress } }
  end,
  update = function(e)
    if not e.scale then return end
    lp.scale = e.scale
    if lp.open then
      lp.progress = 1 - lp_clamp((e.scale - 1) / (LP_FULL_SPREAD - 1))
    else
      lp.progress = lp_clamp((LP_START - e.scale) / (LP_START - LP_FULL))
    end
    table.insert(lp.samples, { t = e.time_ms, p = lp.progress })
    if #lp.samples > 64 then table.remove(lp.samples, 1) end
    if lp.open or e.scale < 1 then
      lp_write(string.format("live %.4f", lp.progress))
    end
  end,
  finish = function(e)
    local v = lp_velocity()
    local projected = lp.progress + v * LP_PROJECT_MS
    if lp.open or lp.scale < 1 then
      local target = (not e.cancelled and projected > 0.5) and 1 or 0
      if e.cancelled then target = lp.open and 1 or 0 end
      lp_write(string.format("end %d %.5f", target, v))
    elseif not e.cancelled and lp.scale > 1.3 then
      hl.exec_cmd(os.getenv("HOME") .. "/.local/bin/show-desktop")
    end
  end,
}

-- Thumb + 3 fingers. libinput's thumb detection sometimes drops the thumb
-- (it sits low on the pad and presses wide), which leaves a 3-finger pinch, so
-- that runs the same handler. 3-finger swipes (workspaces) are unaffected.
-- The open Launchpad inhibits binds/gestures; these must still work.
hl.gesture({ fingers = 4, direction = "pinch", disable_inhibit = true, action = lp_action })
hl.gesture({ fingers = 3, direction = "pinch", disable_inhibit = true, action = lp_action })

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
