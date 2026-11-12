# Elune

Omarchy theme: moonlit violet night, silver dotted line-art, moonwell teal.

Regenerate the images (ImageMagick 7, Python 3; ffmpeg for the live loop):

    cd ~/.config/omarchy/themes/elune
    ELUNE_LAYERS=/tmp/elune-layers ./generate-emblem.py emblem.txt .   # backgrounds/0-emblem.webp, unlock.png
    ./generate-live.py /tmp/elune-layers backgrounds/0-emblem-live.mp4  # breathing loop, ~3 min
    ./generate-abstract.py backgrounds                                  # crescent, moonwell, quiet sky

`emblem.txt` is the braille tree also used by the screensaver.
