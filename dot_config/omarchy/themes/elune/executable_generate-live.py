#!/usr/bin/env python3
"""Live Elune emblem: a seamless video loop where the moon glow breathes and the sparkles twinkle.
Layers come from `ELUNE_LAYERS=<dir> generate-emblem.py ...`.
Usage: generate-live.py <layers-dir> <out.mp4> [seconds=8] [fps=24] [width=1920]   (needs ImageMagick 7 + ffmpeg)"""
import atexit, json, math, os, shutil, subprocess, sys, tempfile
from concurrent.futures import ThreadPoolExecutor

src, out = os.path.abspath(sys.argv[1]), os.path.abspath(sys.argv[2])
T = float(sys.argv[3]) if len(sys.argv) > 3 else 8
FPS = int(sys.argv[4]) if len(sys.argv) > 4 else 24
OW = int(sys.argv[5]) if len(sys.argv) > 5 else 1920
meta = json.load(open(os.path.join(src, "sparkles.json")))
S = OW / meta["W"]
OH = round(meta["H"] * S)
N = round(T * FPS)
# temp files on disk (/tmp is RAM here and video frames are GBs), removed even on failure
os.makedirs(os.path.expanduser("~/.cache"), exist_ok=True)
tmp = tempfile.mkdtemp(prefix="elune-", dir=os.path.expanduser("~/.cache"))
atexit.register(shutil.rmtree, tmp, True)
p = lambda n: os.path.join(tmp, n)
magick = lambda *a: subprocess.run(["magick", *map(str, a)], check=True)

# scale the layers once; one shared grain frame keeps the gradients from banding without costing bitrate
for n in ("sky", "moon", "dust", "emblem"):
    magick(os.path.join(src, n + ".png"), "-resize", f"{OW}x{OH}!", p(n + ".png"))
magick("-seed", 1, "-size", f"{OW}x{OH}", "xc:gray50", "-attenuate", ".35", "+noise", "Gaussian", "-colorspace", "gray", p("grain.png"))

# every period divides the loop, so frame N wraps to frame 0 without a seam
sparks = [(x * S, y * S, r * S, col, a, (i * 7) % 3 + 1, (i * 2.399) % (2 * math.pi))
          for i, (x, y, r, col, a) in enumerate(meta["sparkles"])]

def sparkle(x, y, r, color, alpha):
    t = r * .16
    return (f"fill '{color}' fill-opacity {alpha:.3f} "
            f"polygon {x:.1f},{y - r:.1f} {x + t:.1f},{y:.1f} {x:.1f},{y + r:.1f} {x - t:.1f},{y:.1f} "
            f"polygon {x - r:.1f},{y:.1f} {x:.1f},{y - t:.1f} {x + r:.1f},{y:.1f} {x:.1f},{y + t:.1f}")

def frame(i):
    ph = 2 * math.pi * i / N
    breath = .5 - .5 * math.cos(ph)                 # 0 -> 1 -> 0 over the loop
    moon, glow = .80 + .20 * breath, .9 + .1 * breath
    draw = " ".join(sparkle(x, y, r * (.85 + .15 * tw), col, a * (.25 + .75 * tw))
                    for x, y, r, col, a, k, off in sparks
                    for tw in [.5 + .5 * math.sin(k * ph + off)])
    magick(p("sky.png"),
           "(", p("moon.png"), "-evaluate", "multiply", f"{moon:.4f}", ")", "-compose", "screen", "-composite",
           p("dust.png"), "-compose", "screen", "-composite",
           "(", "-size", f"{OW}x{OH}", "xc:black", "-draw", draw, "(", "+clone", "-blur", f"0x{6 * S:.1f}", "-level", "0,55%", ")",
           "-compose", "screen", "-composite", ")", "-compose", "screen", "-composite",
           "(", p("emblem.png"), "-channel", "RGB", "-evaluate", "multiply", f"{glow:.4f}", "+channel", ")",
           "-compose", "over", "-composite",
           p("grain.png"), "-compose", "overlay", "-composite", p(f"f{i:04d}.png"))

with ThreadPoolExecutor(os.cpu_count() or 4) as ex:
    list(ex.map(frame, range(N)))
subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-framerate", str(FPS), "-i", p("f%04d.png"),
                "-c:v", "libx264", "-preset", "slow", "-crf", "14", "-tune", "grain", "-pix_fmt", "yuv420p",
                "-movflags", "+faststart", out], check=True)
print(out, N, "frames")
