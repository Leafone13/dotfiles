#!/bin/bash
# Pre-blur the current Omarchy wallpaper for the Launchpad background.
# Downscale -> blur -> upscale looks the same as a big live blur at a fraction
# of the cost. Regenerates only when the wallpaper (path or mtime) changes.
# Slightly desaturated (vibrancy) so loud wallpapers fight the text less.
# Prints the blurred image path.
set -e
src=$(readlink -f "${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/current/background" 2>/dev/null || true)
cache="${XDG_CACHE_HOME:-$HOME/.cache}/omarchy-launchpad"
out="$cache/blur.jpg"
stamp="$cache/blur.stamp"
mkdir -p "$cache"
[ -f "$src" ] || { echo ""; exit 0; }
key="v2 $src $(stat -c %Y "$src")"
if [ ! -f "$out" ] || [ "$(cat "$stamp" 2>/dev/null)" != "$key" ]; then
  magick "$src" -resize 320x -blur 0x7 -modulate 100,75 -resize 1600x -quality 92 "$out.tmp.jpg"
  mv "$out.tmp.jpg" "$out"
  echo "$key" > "$stamp"
fi
echo "$out"
