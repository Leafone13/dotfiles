#!/usr/bin/env python3
"""Elune wallpaper (to ~/.config/omarchy/backgrounds/elune) + unlock logo (to <out-dir>) from the braille tree emblem (emblem.txt).
Usage: generate-emblem.py <braille.txt> <out-dir> [seed]   (needs ImageMagick 7)"""
import atexit, math, os, random, shutil, subprocess, sys, tempfile

src, outdir = sys.argv[1], os.path.abspath(sys.argv[2])
rnd = random.Random(int(sys.argv[3]) if len(sys.argv) > 3 else 3)
W, H = 2560, 1440
CX, CY = W // 2, H // 2 - 10
# temp files on disk (/tmp is RAM here and video frames are GBs), removed even on failure
os.makedirs(os.path.expanduser("~/.cache"), exist_ok=True)
tmp = tempfile.mkdtemp(prefix="elune-", dir=os.path.expanduser("~/.cache"))
atexit.register(shutil.rmtree, tmp, True)
p = lambda n: os.path.join(tmp, n)
magick = lambda *a: subprocess.run(["magick", *map(str, a)], check=True)

# braille cell bit -> (dx, dy) on the 2x4 dot grid
BITS = [(0, 0), (0, 1), (0, 2), (1, 0), (1, 1), (1, 2), (0, 3), (1, 3)]
dots = []
for row, line in enumerate(open(src, encoding="utf-8").read().splitlines()):
    for col, ch in enumerate(line):
        v = ord(ch) - 0x2800
        if 0 < v < 256:
            dots += [(col * 2 + dx, row * 4 + dy) for b, (dx, dy) in enumerate(BITS) if v >> b & 1]
assert len(dots) > 300, f"too few dots parsed: {len(dots)}"
xs, ys = [d[0] for d in dots], [d[1] for d in dots]
gw, gh = max(xs) - min(xs), max(ys) - min(ys)

def emblem(size_h, r, color, name, pad=0):
    """Draw the dots as circles, emblem height size_h px; returns (path, w, h)."""
    s = size_h / gh
    w, h = int(gw * s) + 2 * pad + 2 * r + 2, int(size_h) + 2 * pad + 2 * r + 2
    circles = " ".join(f"circle {(x - min(xs)) * s + pad + r + 1:.1f},{(y - min(ys)) * s + pad + r + 1:.1f} "
                       f"{(x - min(xs)) * s + pad + 2 * r + 1:.1f},{(y - min(ys)) * s + pad + r + 1:.1f}" for x, y in dots)
    magick("-size", f"{w}x{h}", "xc:none", "-fill", color, "-draw", circles, p(name))
    return p(name), w, h

def sparkle(x, y, r, color, alpha):
    """Four-point star like ✦: two thin diamonds."""
    t = r * .16
    return (f"fill '{color}' fill-opacity {alpha:.2f} "
            f"polygon {x},{y - r} {x + t},{y} {x},{y + r} {x - t},{y} "
            f"polygon {x - r},{y} {x},{y - t} {x + r},{y} {x},{y + t}")

# --- wallpaper ---
EH = 760                                    # emblem height on screen
em, ew, eh = emblem(EH, 3.1, "#ece8ff", "em.png", pad=60)
R = EH * .56                                # moon radius around the emblem
magick("-size", f"{W}x{H}", "radial-gradient:#1d1a3a-#07060e", p("sky.png"))
# moon: faint disc, a lighter inner glow, wide violet halo, thin silver rim
magick("-size", f"{W}x{H}", "xc:black",
       "-fill", "#3b2f86", "-draw", f"circle {CX},{CY} {CX + R * 1.55},{CY}", "-blur", "0x160",
       "(", "-size", f"{W}x{H}", "xc:black", "-fill", "#2a2552", "-draw", f"circle {CX},{CY} {CX + R},{CY}", "-blur", "0x3", ")",
       "-compose", "screen", "-composite",
       "(", "-size", f"{W}x{H}", "xc:black", "-fill", "#4a3f8f", "-draw", f"circle {CX},{CY - R * .18} {CX + R * .62},{CY}",
       "-blur", "0x110", ")", "-compose", "screen", "-composite",
       "(", "-size", f"{W}x{H}", "xc:black", "-fill", "none", "-stroke", "#9d90e0", "-strokewidth", 2,
       "-draw", f"circle {CX},{CY} {CX + R},{CY}", "-blur", "0x1.2", "(", "+clone", "-blur", "0x14", ")",
       "-compose", "screen", "-composite", ")", "-compose", "screen", "-composite", p("moon.png"))
# emblem glow: crisp dots + soft bloom in accent violet
magick(em, "(", "+clone", "-fill", "#b8a7ff", "-colorize", 100, "-blur", "0x9", ")", "-compose", "dst-over", "-composite",
       p("emglow.png"))
# stars: faint dust + braille-like dots + ✦ sparkles, thinned inside the moon
dust = []
for _ in range(900):
    x, y = rnd.uniform(0, W), rnd.uniform(0, H)
    if math.hypot(x - CX, y - CY) < R * 1.08:
        continue
    r, a = rnd.choice([.7, .9, 1.1, 1.4]), rnd.uniform(.25, .8)
    dust.append(f"fill 'rgba(225,220,255,{a:.2f})' circle {x:.1f},{y:.1f} {x + r:.1f},{y:.1f}")
spark, spark_params = [], []
for _ in range(26):
    while True:
        x, y = rnd.uniform(60, W - 60), rnd.uniform(60, H - 60)
        if math.hypot(x - CX, y - CY) > R * 1.25:
            break
    sp = (round(x), round(y), rnd.choice([7, 9, 12, 16, 22]), rnd.choice(["#efeaff", "#cfc4ff", "#bfeff2"]), rnd.uniform(.55, 1))
    spark_params.append(sp)
    spark.append(sparkle(*sp))
with open(p("stars.mvg"), "w") as f:
    f.write("\n".join(dust + spark) + "\n")
magick("-size", f"{W}x{H}", "xc:black", "-draw", f"@{p('stars.mvg')}",
       "(", "+clone", "-blur", "0x6", "-level", "0,55%", ")", "-compose", "screen", "-composite", p("stars.png"))

# wallpaper goes to the local backgrounds folder, never into the theme (the theme is in public chezmoi)
walldir = os.path.expanduser("~/.config/omarchy/backgrounds/elune")
os.makedirs(walldir, exist_ok=True)
wall = os.path.join(walldir, "0-emblem.webp")
magick(p("sky.png"), p("moon.png"), "-compose", "screen", "-composite", p("stars.png"), "-compose", "screen", "-composite",
       p("emglow.png"), "-geometry", f"+{CX - ew // 2}+{CY - eh // 2}", "-compose", "over", "-composite",
       # fine grain so the gradients don't band
       "(", "-size", f"{W}x{H}", "xc:gray50", "-attenuate", ".35", "+noise", "Gaussian", "-colorspace", "gray", ")",
       "-compose", "overlay", "-composite", "-quality", 93, wall)

# --- unlock.png for the boot password screen: emblem in accent colour, transparent, like stock (height 188) ---
lg, lw, lh = emblem(180, 1.45, "#b8a7ff", "logo.png")
magick(lg, "-background", "none", "-gravity", "center", "-extent", f"{max(lw, 188)}x188", os.path.join(outdir, "unlock.png"))

# layers for the live (video) version: ELUNE_LAYERS=<dir> elune_emblem.py ...
layers = os.environ.get("ELUNE_LAYERS")
if layers:
    import json, shutil
    os.makedirs(layers, exist_ok=True)
    for n in ("sky.png", "moon.png"):
        shutil.copy(p(n), os.path.join(layers, n))
    magick("-size", f"{W}x{H}", "xc:none", p("emglow.png"), "-geometry", f"+{CX - ew // 2}+{CY - eh // 2}",
           "-compose", "over", "-composite", os.path.join(layers, "emblem.png"))
    with open(p("dust.mvg"), "w") as f:
        f.write("\n".join(dust) + "\n")
    magick("-size", f"{W}x{H}", "xc:black", "-draw", f"@{p('dust.mvg')}",
           "(", "+clone", "-blur", "0x6", "-level", "0,55%", ")", "-compose", "screen", "-composite",
           os.path.join(layers, "dust.png"))
    json.dump({"W": W, "H": H, "sparkles": spark_params}, open(os.path.join(layers, "sparkles.json"), "w"))
print(wall)
