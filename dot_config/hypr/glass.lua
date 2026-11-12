-- Window look per mode of the bar button logos.glass (cycle.sh: clear, frosted, original).
-- Loaded after Omarchy's toggles, so these win.
local function exists(path)
  local f = io.open(path)
  if f then f:close() end
  return f ~= nil
end

-- Frosted: denser, darker blur than Omarchy's default, so text stays readable over bright wallpapers.
-- Always set, so the glassy bar looks the same in every window mode; does nothing while nothing is glassy.
hl.config({ decoration = { blur = { size = 10, passes = 3, brightness = 0.45, vibrancy = 0.2 } } })

-- Clear (logos.glass marker): Omarchy's see-through windows are barely see-through (0.985 / 0.96);
-- make them clearly so. Without the marker the stock look stays ("original" in the button's cycle).
if exists((os.getenv("XDG_STATE_HOME") or (os.getenv("HOME") .. "/.local/state")) .. "/logos-glass/clear") then
  o.window({ tag = "transparent-window" }, { opacity = "0.9 0.85" })
end

-- Window opacity eases like the bar does (its colour change: 250 ms, ease-out), instead of jumping.
-- Also softens the active/inactive opacity step when focus moves.
hl.animation({ leaf = "fadeSwitch", enabled = true, speed = 2.5, bezier = "easeOutQuint" })
