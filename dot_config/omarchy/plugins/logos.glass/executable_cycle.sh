#!/bin/bash
# One press = next look for bar and windows together:
#   clear    (see-through windows 0.9, bar clear)                    -> frosted
#   frosted  (glassy windows and bar, my dense dark blur)            -> light
#   light    (glassy windows and bar, Omarchy's own light blur)      -> original
#   original (Omarchy's stock see-through windows 0.985, bar clear)  -> clear
# Omarchy has one "transparent" window mode for both clear and original, and one "glassy" for
# frosted and light; the marker files tell them apart for ~/.config/hypr/glass.lua.
state="${XDG_STATE_HOME:-$HOME/.local/state}/logos-glass"
windows=$(omarchy hyprland window transparency)
mkdir -p "$state"

if [[ $windows == glassy && -f $state/light ]]; then
  rm -f "$state/light"; windows=transparent; bar=none       # -> original
elif [[ $windows == glassy ]]; then
  touch "$state/light"; hyprctl reload >/dev/null; exit     # -> light: only the blur changes
elif [[ $windows == transparent && -f $state/clear ]]; then
  rm -f "$state/clear"; windows=glassy; bar=glassy          # -> frosted
else
  touch "$state/clear"; windows=transparent; bar=none       # -> clear
fi

# one after the other: both reload Hyprland when glass goes on or off, and run together they
# may race (suspected cause of flicker and of bar and windows briefly out of step; not proven)
omarchy hyprland window transparency "$windows" && omarchy bar background "$bar"
