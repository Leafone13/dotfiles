#!/usr/bin/env python3
"""Abstract Elune wallpapers: crescent, moonwell, quiet sky. Detail lives at the edges,
the centre stays calm because windows cover it.
Usage: generate-abstract.py <out-dir> [seed]   (needs ImageMagick 7)"""
import atexit, math, os, random, shutil, subprocess, sys, tempfile

outdir = os.path.abspath(sys.argv[1])
seed = int(sys.argv[2]) if len(sys.argv) > 2 else 5
W, H = 2560, 1440
# temp files on disk (/tmp is RAM here and video frames are GBs), removed even on failure
os.makedirs(os.path.expanduser("~/.cache"), exist_ok=True)
tmp = tempfile.mkdtemp(prefix="elune-", dir=os.path.expanduser("~/.cache"))
atexit.register(shutil.rmtree, tmp, True)
p = lambda n: os.path.join(tmp, n)
magick = lambda *a: subprocess.run(["magick", *map(str, a)], check=True)
os.makedirs(outdir, exist_ok=True)

def sparkle(x, y, r, color, alpha):
    t = r * .16
    return (f"fill '{color}' fill-opacity {alpha:.2f} "
            f"polygon {x:.1f},{y - r:.1f} {x + t:.1f},{y:.1f} {x:.1f},{y + r:.1f} {x - t:.1f},{y:.1f} "
            f"polygon {x - r:.1f},{y:.1f} {x:.1f},{y - t:.1f} {x + r:.1f},{y:.1f} {x:.1f},{y + t:.1f}")

def edge_weight(x, y):
    """0 in the middle of the screen, 1 at the edges."""
    dx, dy = abs(x - W / 2) / (W / 2), abs(y - H / 2) / (H / 2)
    return min(1, max(dx, dy) ** 1.6 * 1.15)

def starfield(rnd, n_dust, n_spark, keep=lambda x, y: True, edge=True):
    out = []
    for _ in range(n_dust):
        x, y = rnd.uniform(0, W), rnd.uniform(0, H)
        if not keep(x, y) or (edge and rnd.random() > .04 + .96 * edge_weight(x, y)):
            continue
        r, a = rnd.choice([.6, .8, 1, 1.3]), rnd.uniform(.2, .75)
        out.append(f"fill 'rgba(225,220,255,{a:.2f})' circle {x:.1f},{y:.1f} {x + r:.1f},{y:.1f}")
    placed = 0
    while placed < n_spark:
        x, y = rnd.uniform(50, W - 50), rnd.uniform(50, H - 50)
        if not keep(x, y) or (edge and edge_weight(x, y) < .55):
            continue
        out.append(sparkle(x, y, rnd.choice([6, 8, 10, 13, 18]), rnd.choice(["#efeaff", "#cfc4ff", "#bfeff2"]),
                           rnd.uniform(.5, .95)))
        placed += 1
    return out

def stars_layer(name, cmds, bloom=.55):
    with open(p(name + ".mvg"), "w") as f:
        f.write("\n".join(cmds) + "\n")
    magick("-size", f"{W}x{H}", "xc:black", "-draw", f"@{p(name + '.mvg')}",
           "(", "+clone", "-blur", "0x6", "-level", f"0,{bloom * 100:.0f}%", ")", "-compose", "screen", "-composite",
           p(name + ".png"))
    return p(name + ".png")

def finish(layers, out):
    """Screen layers over the first one, add fine grain against banding."""
    args = [layers[0]]
    for l in layers[1:]:
        args += [l, "-compose", "screen", "-composite"]
    magick(*args, *GRAIN, "-quality", 93, os.path.join(outdir, out))

# grey film grain, overlay at low strength: no colour speckle on near-black
GRAIN = ["(", "-size", f"{W}x{H}", "xc:gray50", "-attenuate", ".35", "+noise", "Gaussian", "-colorspace", "gray", ")",
         "-compose", "overlay", "-composite"]

def ring_dots(rnd, specs):
    """Concentric rings of fine dots, violet fading to teal. Returns (draw cmds, [(cx, cy, r), ...])."""
    dots, radii = [], []
    for cx, cy, n, r0, step in specs:
        for i in range(n):
            r = r0 + i * step * (1 + i * .025)
            radii.append((cx, cy, r))
            f = i / max(n - 1, 1)
            a = .85 * (1 - f) ** 1.3 + .05
            col = tuple(round(v1 + (v2 - v1) * f) for v1, v2 in zip((184, 167, 255), (142, 217, 232)))
            size, gap = 2.6 - 1.4 * f, 11 + 6 * f
            k, ph = int(2 * math.pi * r / gap), rnd.uniform(0, 6.283)
            for j in range(k):
                t = ph + j * 2 * math.pi / k
                x, y = cx + r * math.cos(t), cy + r * math.sin(t)
                if -10 < x < W + 10 and -10 < y < H + 10:
                    dots.append(f"fill 'rgba({col[0]},{col[1]},{col[2]},{a:.2f})' circle {x:.1f},{y:.1f} {x + size:.1f},{y:.1f}")
    return dots, radii

def off_rings(radii, margin=10):
    return lambda x, y: all(abs(math.hypot(x - cx, y - cy) - r) > margin for cx, cy, r in radii)

# 1. Crescent: a thin silver arc high on the right, the unlit disc barely there
rnd = random.Random(seed)
MX, MY, R = 2140, 330, 150
magick("-size", f"{W * 2}x{H * 2}", "radial-gradient:#17142f-#06050d", "-crop", f"{W}x{H}+{W - MX + 300}+{H - MY - 150}",
       "+repage", p("sky1.png"))
magick("-size", f"{W}x{H}", "xc:black",
       # lit crescent = disc minus an offset disc
       "(", "-size", f"{W}x{H}", "xc:black", "-fill", "#f3efff", "-draw", f"circle {MX},{MY} {MX + R},{MY}",
       "-fill", "black", "-draw", f"circle {MX - R * .17},{MY - R * .08} {MX - R * .17 + R * .99},{MY - R * .08}",
       "-blur", "0x1", "(", "+clone", "-blur", "0x18", ")", "-compose", "screen", "-composite",
       "(", "+clone", "-blur", "0x90", "-fill", "#6a58d0", "-tint", 100, ")", "-compose", "screen", "-composite", ")",
       "-compose", "screen", "-composite", p("moon1.png"))
# the unlit part = moon disc AND the offset disc: cut the glow there so it reads as a silhouette
OX, OY, OR = MX - R * .17, MY - R * .08, R * .99
magick("-size", f"{W}x{H}", "xc:black", "-fill", "white", "-draw", f"circle {MX},{MY} {MX + R},{MY}",
       "(", "-size", f"{W}x{H}", "xc:black", "-fill", "white", "-draw", f"circle {OX},{OY} {OX + OR},{OY}", ")",
       "-compose", "multiply", "-composite", "-alpha", "off", "-blur", "0x2.5", p("shadow.png"))
magick(p("moon1.png"), "(", p("shadow.png"), "-negate", ")", "-compose", "multiply", "-composite",
       p("moon1.png"))
far = lambda x, y: math.hypot(x - MX, y - MY) > R * 1.5
finish([p("sky1.png"), p("moon1.png"), stars_layer("st1", starfield(rnd, 1100, 22, far))], "1-crescent.webp")

# 2. Moonwell: rings of fine dots rising from the lower-left corner, violet fading into teal
rnd = random.Random(seed + 1)
magick("-size", f"{W * 2}x{H * 2}", "radial-gradient:#161a38-#07060e", "-crop", f"{W}x{H}+{W - 250}+{H - 1400}",
       "+repage", p("sky2.png"))
dots, radii = ring_dots(rnd, [(260, H + 120, 10, 160, 78), (W - 180, -140, 7, 120, 70)])
rings = stars_layer("rings", dots, bloom=.7)
# light the well itself: soft teal glow in the corner
magick("-size", f"{W}x{H}", "xc:black", "-fill", "#123a44", "-draw", f"circle 260,{H + 120} 760,{H + 120}", "-blur", "0x160",
       p("well.png"))
finish([p("sky2.png"), p("well.png"), rings, stars_layer("st2", starfield(rnd, 700, 12, off_rings(radii)))], "2-moonwell.webp")

# 3. Quiet sky: near-empty dark, one faint dotted arc from the top-right, dust and sparkles only at the edges
rnd = random.Random(seed + 2)
magick("-size", f"{W}x{H}", "gradient:#100e22-#06050c", p("sky3.png"))
arc, arc_radii = ring_dots(rnd, [(W + 200, -300, 5, 500, 90)])
finish([p("sky3.png"), stars_layer("arc", arc, bloom=.7),
        stars_layer("st3", starfield(rnd, 500, 16, off_rings(arc_radii)))], "3-quiet-sky.webp")
print(outdir)
