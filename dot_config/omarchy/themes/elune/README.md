# Elune

Omarchy theme: moonlit violet night, silver dotted line-art, moonwell teal.

The theme ships the palette (`colors.toml`), a slowly turning border gradient for the focused window (`hyprland.lua`),
the boot/lock logo (`unlock.png`) and the braille tree (`emblem.txt`, also used by the screensaver).
It ships no wallpapers: those live locally in `~/.config/omarchy/backgrounds/elune/`, outside this repo.

Regenerate the images (ImageMagick 7, Python 3; ffmpeg for the live loop). Temp files go to `~/.cache`.

    cd ~/.config/omarchy/themes/elune
    ELUNE_LAYERS=~/.cache/elune-layers ./generate-emblem.py emblem.txt .   # unlock.png here, 0-emblem.webp to the local backgrounds
    ./generate-live.py ~/.cache/elune-layers ~/.config/omarchy/backgrounds/elune/0-emblem-live.mp4   # breathing loop, ~3 min
    ./generate-abstract.py ~/.config/omarchy/backgrounds/elune                                         # crescent, moonwell, quiet sky

After adding or removing wallpapers run `omarchy theme set elune`.
