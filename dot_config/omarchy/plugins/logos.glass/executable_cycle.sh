#!/bin/bash
# One press = next look for bar and windows together:
#   clear    (see-through windows 0.9, bar clear)      -> frosted
#   frosted  (glassy windows and bar)                  -> original
#   original (Omarchy's stock see-through windows 0.985, bar clear) -> clear
# Omarchy has one "transparent" window mode for both clear and original; the marker file
# tells them apart and makes ~/.config/hypr/glass.lua apply the 0.9 opacity.
marker="${XDG_STATE_HOME:-$HOME/.local/state}/logos-glass/clear"
windows=$(omarchy hyprland window transparency)

if [[ $windows == glassy ]]; then
  rm -f "$marker"; windows=transparent; bar=none            # -> original
elif [[ $windows == transparent && -f $marker ]]; then
  rm -f "$marker"; windows=glassy; bar=glassy               # -> frosted
else
  mkdir -p "${marker%/*}" && touch "$marker"; windows=transparent; bar=none   # -> clear
fi

# one after the other: both reload Hyprland when glass goes on or off, and run together they
# may race (suspected cause of flicker and of bar and windows briefly out of step; not proven)
omarchy hyprland window transparency "$windows" && omarchy bar background "$bar"
