#!/bin/bash
# Make the light mask for a wallpaper, one channel per effect:
#   R = the emblem's bright lines inside a soft disc, plus their halo (breath, wave)
#   G = distance from the trunk's foot, 0 at the foot to 1 at three radii (the wave climbs along it,
#       the sky turns around it)
#   B = the sky that may flow: smooth paint only, never the emblem, never a still zone
# and, when a creature is given, <wallpaper>.life.png:
#   R, G = which way and how far each of its pixels moves on an inhale (grey = stays), B = its eye
# and, when petals are given, <wallpaper>.petals.png: three of the painted petals cut out, side by side
# and, when sway is given, <wallpaper>.sway.png: R, G = how far each pixel of a bough swings per radian
#   (grey = stays), a small turn around the point it hangs from
# and, when near is given, <wallpaper>.depth.png: flat plates, 0 = far, 0.5 = the emblem, 0.7 = near things,
#   rising to 1 at the bottom edge (the ground comes toward the viewer)
# Usage: mask.sh <wallpaper> <centre-x> <centre-y> <radius> [still zones] [creature] [petals] [sway] [near]
#   centre and radius: the emblem circle, in wallpaper pixels
#   still zones: ImageMagick draw commands in mask pixels (1920x1080) for what must not move
#   creature, in mask pixels: "feet-x feet-y  body-x body-y body-rx body-ry  eye-x eye-y eye-r";
#     the body ellipse swells away from the feet and fades out at its rim
#   petals: three "x,y,size" boxes around painted petals, centre and side in wallpaper pixels
#   sway, in mask pixels: one or more "pivot-x pivot-y  centre-x centre-y rx ry  gain": what lies in the
#     ellipse turns around the pivot (where it hangs from the limb, never on the trunk), fading out at
#     the rim; gain makes a short cluster swing as far as a long twig. Must sit inside a still zone.
#   near: ImageMagick draw commands in mask pixels for what stands in front of the sky. Each plate moves
#     whole, so its edge must lie outside the painted thing, in smooth sky, 20 px or more from it.
# Each petal's circle reaches 35 px past it: flowing sky nearer than its own travel shows the petal twice.
# The whole of 0-moonlight.png (still: tree + owl + hill, moon, each painted petal; the owl; three petals;
# the leaf cluster and the twig of the bough on the left; near: tree + owl + hill, the ground along the bottom):
#   ./mask.sh ~/.config/omarchy/backgrounds/elune/0-moonlight.png 1293 666 484 \
#     "polygon 0,0 840,0 840,140 460,260 300,410 450,500 450,730 670,865 1010,1080 0,1080 circle 1600,95 1600,205 circle 418,285 418,365 circle 224,346 224,436 circle 159,496 159,576 circle 580,636 580,716 circle 1764,245 1764,360 circle 1661,437 1661,535 circle 1738,686 1738,800 circle 1524,804 1524,900 circle 1339,850 1339,950" \
#     "367 697  335 590 105 140  397.5 520.6 7" \
#     "2353,326,230 2214,582,170 1786,1133,150" \
#     "440 72  455 150 105 90  2   520 62  700 55 205 85  1" \
#     "polygon 0,0 840,0 840,140 460,260 300,410 480,480 490,730 670,865 1010,1080 0,1080 polygon 900,1080 1010,1010 1400,1030 1700,990 1920,900 1920,1080"
# After changing light.frag: /usr/lib/qt6/bin/qsb --qt6 -o light.frag.qsb light.frag
# After any change here, in Service.qml or to a mask: omarchy restart shell (a running shell keeps what it loaded)
set -euo pipefail
src=$1 cx=$2 cy=$3 r=$4 still=${5:-} creature=${6:-} petals=${7:-} sway=${8:-} near=${9:-}
out=~/.local/share/elune-breath/$(basename "$src").mask.png
mkdir -p "$(dirname "$out")"
w=$(magick identify -format %w "$src")
s() { echo $(( $1 * 1920 / w )); }   # wallpaper pixels -> mask pixels
mx=$(s $cx) my=$(s $cy) mr=$(s $r)
magick \
  \( "$src" -colorspace gray -level 55%,92% \
     \( +clone -fill black -colorize 100 -fill white -draw "circle $cx,$cy $cx,$((cy + r))" -blur 0x40 \) \
     -compose multiply -composite \
     \( +clone -blur 0x12 \) \( +clone -blur 0x45 \) -background black -compose screen -flatten -resize 1920x1080! \) \
  \( -size 1920x1080 -define gradient:center=$mx,$((my + mr * 3 / 4)) -define gradient:radii=$((3 * mr)),$((3 * mr)) radial-gradient:black-white \) \
  \( "$src" -resize 1920x1080! -colorspace gray \
     \( +clone -morphology Convolve Sobel:90 \) \( -clone 0 -morphology Convolve Sobel:0 \) -delete 0 \
     -compose plus -composite -evaluate abs 0 -blur 0x4 -level 4%,10% -negate -morphology Erode Disk:9 \
     \( -size 1920x1080 xc:white -fill black -draw "circle $mx,$my $mx,$((my + mr * 117 / 100)) $still" -blur 0x28 \) \
     -compose multiply -composite -blur 0x14 -level 5%,75% \) \
  -combine -alpha off -depth 8 "$out"
echo "$out"

if [ -n "$petals" ]; then
  # a petal is brighter than the sky behind it: its own brightness is its outline, faded out toward the box
  sprites=()
  for box in $petals; do
    IFS=, read -r px py ps <<<"$box"
    sprites+=( \( "$src" -crop "${ps}x${ps}+$((px - ps / 2))+$((py - ps / 2))" +repage -resize 128x128 \
      \( +clone -colorspace gray -level 38%,64% -blur 0x0.8 \
         \( -size 128x128 radial-gradient:white-black -level 12%,45% \) -compose multiply -composite \) \
      -alpha off -compose copyopacity -composite \) )
  done
  magick "${sprites[@]}" -background none +append "${out%.mask.png}.petals.png"
  echo "${out%.mask.png}.petals.png"
fi

if [ -n "$sway" ]; then
  # 16 bits until the end: the groups are added up, and grey must stay exactly grey where nothing moves
  magick -size 1920x1080 -depth 16 xc:gray50 "$out.sx.png"
  cp "$out.sx.png" "$out.sy.png"
  set -- $sway
  while [ $# -ge 7 ]; do
    ax=$1 ay=$2 bx=$3 by=$4 brx=$5 bry=$6 gain=$7; shift 7
    x0=$((bx - brx - 4)) y0=$((by - bry - 4)); x0=$((x0 < 0 ? 0 : x0)) y0=$((y0 < 0 ? 0 : y0))
    bw=$((bx + brx + 4 - x0)) bh=$((by + bry + 4 - y0))
    rim="ee=hypot((i+$x0-$bx)/$brx,(j+$y0-$by)/$bry); ww=ee<0.55?1:(ee>1?0:0.5+0.5*cos(pi*(ee-0.55)/0.45));"
    # a turn moves a pixel across its arm: (x, y) from the pivot goes toward (-y, x); 800 px per radian = full scale
    magick "$out.sx.png" \( -size ${bw}x$bh -depth 16 xc:black -fx "$rim 0.5-(j+$y0-$ay)*$gain/800*ww" \) \
      -geometry +$x0+$y0 -compose Mathematics -define compose:args=0,1,1,-0.5 -composite "$out.sx.png"
    magick "$out.sy.png" \( -size ${bw}x$bh -depth 16 xc:black -fx "$rim 0.5+(i+$x0-$ax)*$gain/800*ww" \) \
      -geometry +$x0+$y0 -compose Mathematics -define compose:args=0,1,1,-0.5 -composite "$out.sy.png"
  done
  magick "$out.sx.png" "$out.sy.png" \( -size 1920x1080 xc:black \) -combine -alpha off -depth 8 "${out%.mask.png}.sway.png"
  rm "$out.sx.png" "$out.sy.png"
  echo "${out%.mask.png}.sway.png"
fi

if [ -n "$near" ]; then
  # the plates reach 20 px past what they hold and fade over the next 40: only smooth sky stretches
  magick \( -size 1920x1080 xc:black -fill white -draw "$near" -morphology Dilate Disk:20 -blur 0x10 \) \
    \( -size 1920x650 xc:'gray(70%)' \( -size 1920x430 gradient:'gray(70%)-white' \) -append \) -compose multiply -composite \
    \( -size 1920x1080 xc:black -fill gray50 -draw "circle $mx,$my $mx,$((my + mr * 117 / 100 + 20))" -blur 0x10 \) \
    -compose lighten -composite -depth 8 "${out%.mask.png}.depth.png"
  echo "${out%.mask.png}.depth.png"
fi

[ -n "$creature" ] || exit 0
read -r ax ay bx by brx bry ex ey er <<<"$creature"
# worked out on a box around the body only (-fx is slow), then set into a grey canvas
x0=$((bx - brx - 4)) y0=$((by - bry - 4)) bw=$((2 * brx + 8)) bh=$((2 * bry + 8))
rim="ee=hypot((i+$x0-$bx)/$brx,(j+$y0-$by)/$bry); ww=ee<0.55?1:(ee>1?0:0.5+0.5*cos(pi*(ee-0.55)/0.45));"
magick -size 1920x1080 xc:gray50 \
  \( -size ${bw}x$bh xc:black -fx "$rim 0.5+(i+$x0-$ax)/400*ww" \) -geometry +$x0+$y0 -composite "$out.r.png"
magick -size 1920x1080 xc:gray50 \
  \( -size ${bw}x$bh xc:black -fx "$rim 0.5+(j+$y0-$ay)/400*ww" \) -geometry +$x0+$y0 -composite "$out.g.png"
magick "$out.r.png" "$out.g.png" \
  \( -size 1920x1080 xc:black -fill white -draw "circle $ex,$ey $ex,$(awk "BEGIN { print $ey + $er }")" -blur 0x1.5 \) \
  -combine -alpha off -depth 8 "${out%.mask.png}.life.png"
rm "$out.r.png" "$out.g.png"
echo "${out%.mask.png}.life.png"
