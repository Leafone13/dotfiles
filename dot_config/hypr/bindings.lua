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
o.bind("CTRL + SHIFT + code:49", "Tmux cheatsheet (fullscreen)", "omarchy-shell shell toggle logos.cheatsheet")
-- Launchpad from the keyboard too (the pinch needs the touchpad); Esc closes it.
o.bind("SUPER + code:49", "Launchpad", "omarchy-shell shell toggle logos.launchpad")

-- Hotel AnyDesk picker (~/.local/bin/hotel) (SUPER+SHIFT+A was: ChatGPT)
hl.unbind("SUPER + SHIFT + A")
o.bind("SUPER + SHIFT + A", "Hotels (AnyDesk)", os.getenv("HOME") .. "/.local/bin/hotel --menu")
