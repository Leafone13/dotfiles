-- Keep only your personal keybinding overrides here. Add new bindings or
-- unbind defaults before replacing them.

-- See current bindings and descriptions:
--   omarchy menu keybindings --print

-- To disable every Omarchy default binding, set this in
-- ~/.config/hypr/hyprland.lua before require("default.hypr.omarchy"), then add
-- only the bindings you want below:
--   omarchy_default_bindings = false

-- To disable all preinstalled app/webapp bindings, set:
--   omarchy_preinstalled_bindings = false

-- Add a new binding.
-- o.bind("SUPER + SHIFT + R", "SSH", "alacritty -e ssh your-server")

-- Change an existing binding by unbinding it first, then binding the key again.
-- This example changes SUPER+SPACE from the launcher to the Omarchy root menu.
-- hl.unbind("SUPER + SPACE")
-- o.bind("SUPER + SPACE", "Omarchy menu", "omarchy-menu toggle root")

-- Disable a default binding without replacing it.
-- hl.unbind("SUPER + SHIFT + B")

-- Logitech MX Keys examples:
hl.unbind("SUPER + SHIFT + S") -- was: Google Maps
o.bind("SUPER + SHIFT + S", nil, "omarchy-capture-screenshot")
-- o.bind("SUPER + H", nil, "voxtype record toggle")
-- o.bind("SUPER + PERIOD", nil, "omarchy-shell shell toggle omarchy.emojis")

-- Terminal
o.bind("SUPER + I", "Terminal", { omarchy = "terminal" })

-- Full screen (moved from SUPER+F)
hl.unbind("SUPER + F") -- was: Full screen
o.bind("SUPER + H", "Full screen", hl.dsp.window.fullscreen({ mode = "fullscreen" }))

-- Close window (SUPER+X was: Universal cut)
hl.unbind("SUPER + X")
o.bind("SUPER + X", "Close window", hl.dsp.window.close())

-- Tmux cheatsheet focused on stock tmux bindings (SUPER+ALT+K was: Omarchy tmux keybindings)
hl.unbind("SUPER + ALT + K")
o.bind("SUPER + ALT + K", "Tmux cheatsheet", os.getenv("HOME") .. "/.local/bin/tmux-cheatsheet")
-- Same cheatsheet fullscreen in the Launchpad style (logos.cheatsheet plugin).
-- code:49 is the grave/tilde key, so it also works on the Russian layout (ё).
o.bind("SUPER + CTRL + code:49", "Tmux cheatsheet (fullscreen)", "omarchy-shell shell toggle logos.cheatsheet")
-- Launchpad from the keyboard too (the pinch needs the touchpad). dont_inhibit:
-- the open Launchpad inhibits binds, and this one must also close it.
hl.unbind("SUPER + grave") -- was: Toggle Quake console (Omarchy 4.5), fired together with the Launchpad
hl.unbind("SUPER + SHIFT + grave") -- was: Move window to Quake console
-- Quake console on trial (2026-11-14), on the key it has in Jedi Academy.
o.bind("CTRL + SHIFT + code:49", "Toggle Quake console", hl.dsp.workspace.toggle_special("qconsole"))
-- The console seeds itself with `omarchy-agent` (default/hypr/qconsole.lua), which hardcodes
-- `claude --permission-mode auto`; start plain claude there instead, so it asks as usual.
-- shortcut: matches that exact command string, so an Omarchy update that changes it brings auto back; recheck after updates.
local exec_cmd = hl.exec_cmd
hl.exec_cmd = function(cmd, rules)
  if cmd == "omarchy-agent" then
    cmd = "bash -c 'cd ~/Work && exec omarchy-launch-tui --app-id=org.omarchy.agent claude'"
  end
  return exec_cmd(cmd, rules)
end
hl.bind("SUPER + code:49", hl.dsp.exec_cmd("omarchy-shell shell toggle logos.launchpad"), { description = "Launchpad", dont_inhibit = true })

-- Hotel AnyDesk picker (~/.local/bin/hotel) (SUPER+SHIFT+A was: ChatGPT)
hl.unbind("SUPER + SHIFT + A")
o.bind("SUPER + SHIFT + A", "Hotels (AnyDesk)", os.getenv("HOME") .. "/.local/bin/hotel --menu")

-- Give Right Alt and Alt + Space back: Left Alt + Right Alt switches the layout (grp:alts_toggle).
hl.unbind("ALT + Alt_R")
hl.unbind("ALT + SPACE")

-- Dictation keys from before Alt + Space and Right Alt became the defaults.
-- Remove these lines to give the keys back to applications.
if o.dictation_installed and o.dictation_installed() then
  o.bind("SUPER + CTRL + X", "Toggle dictation", "omarchy-dictation toggle")
  o.bind_hold("F9", "Start dictation (push-to-talk)", "omarchy-dictation start", "Stop dictation (push-to-talk)", "omarchy-dictation stop")
end

-- Universal copy/paste/select all by keycode, so they also work on the Russian layout:
-- Omarchy's defaults send the key by name ("C"), which the ru layout doesn't have
-- ("send_key_state: key not found"). code:38 = A, code:54 = C, code:55 = V.
local function send_once(mods, key)
  hl.dispatch(hl.dsp.send_key_state({ mods = mods, key = key, state = "down" }))
  hl.timer(function()
    hl.dispatch(hl.dsp.send_key_state({ mods = mods, key = key, state = "up" }))
  end, { timeout = 50, type = "oneshot" })
end

local function in_terminal()
  local window = hl.get_active_window()
  for _, tag in ipairs(window and window.tags or {}) do
    if tag:gsub("%*$", "") == "terminal" then return true end
  end
  return false
end

local function clipboard(key)
  return function() send_once(in_terminal() and "CTRL SHIFT" or "CTRL", key) end
end

o.rebind("SUPER + A", "Select all", function() send_once("CTRL", "code:38") end)
o.rebind("SUPER + C", "Universal copy", clipboard("code:54"))
o.rebind("SUPER + V", "Universal paste", clipboard("code:55"))
