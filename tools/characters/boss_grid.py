#!/usr/bin/env python3
"""Put boss_build.py's renders on a measuring grid (needs Pillow).

    python3 tools/characters/boss_grid.py <cache dir> grid|rig|poses [title]

grid / rig: <name>_front.png + <name>_side.png (and <name>_top.png, if the
recipe asked for one) side by side with a 0.05 grid (0.1 for a wide view:
<name>_view.json), labelled in the normalized model's units, and, for rig,
its bones drawn on top (<name>_bones.json) -> <name>.png. poses: pose_*.png
in a row -> poses.png.
"""
import glob
import json
import os
import sys

from PIL import Image, ImageDraw

cache, name = sys.argv[1], sys.argv[2]
title = sys.argv[3] if len(sys.argv) > 3 else ""
if name == "poses":
    shots = [Image.open(p).convert("RGB") for p in sorted(glob.glob(os.path.join(cache, "pose_*.png")),
                                                          key=lambda p: int(p.rsplit("_", 1)[1].split(".")[0]))]
    w, h = shots[0].size
    sheet = Image.new("RGB", (w * len(shots), h))
    for k, im in enumerate(shots):
        sheet.paste(im, (w * k, 0))
    sheet.save(os.path.join(cache, "poses.png"))
    sys.exit(0)
view = {"span": 0.6, "top": False}
if os.path.exists(os.path.join(cache, name + "_view.json")):
    view = json.load(open(os.path.join(cache, name + "_view.json")))
span = float(view["span"])
step = 0.05 if span <= 0.8 else 0.1
views = ["front", "side"] + (["top"] if view.get("top") else [])
ims = [Image.open(os.path.join(cache, name + "_" + v + ".png")).convert("RGB") for v in views]
bones = json.load(open(os.path.join(cache, name + "_bones.json")))
w, h = ims[0].size
sheet = Image.new("RGB", (w * len(ims) + 10 * (len(ims) - 1), h + 30), (40, 40, 40))
d = ImageDraw.Draw(sheet)
n = int(round(span / step))
for k, im in enumerate(ims):
    ox = k * (w + 10)
    sheet.paste(im, (ox, 30))
    # the views span u in [-span, span] (front: model x; side and top: model
    # y), and z in [-0.05, 2 span - 0.05] (top: model x, its right at the top)
    for i in range(-n, n + 1):
        x = ox + int((i * step + span) / (2 * span) * w)
        col = (200, 60, 60) if i == 0 else ((90, 90, 200) if i % 2 == 0 else (190, 190, 215))
        d.line([(x, 30), (x, 30 + h)], fill=col, width=1)
        if i % 2 == 0:
            d.text((x + 2, 32), "%.1f" % (i * step), fill=(30, 30, 160))
    rows = range(-n, n + 1) if views[k] == "top" else range(0, 2 * n)
    for j in rows:
        z = j * step
        y = 30 + int(((z + span) if views[k] == "top" else (2 * span - 0.05 - z)) / (2 * span) * h)
        col = (200, 60, 60) if j == 0 else ((90, 90, 200) if j % 2 == 0 else (190, 190, 215))
        d.line([(ox, y), (ox + w, y)], fill=col, width=1)
        if j % 2 == 0:
            d.text((ox + 3, y - 12), ("x %.2f" if views[k] == "top" else "%.2f") % z, fill=(30, 30, 160))
    d.text((ox + 8, 8), {"front": "FRONT (image right = model +x, its left)",
                         "side": "SIDE from +x (image right = model +y, its back)",
                         "top": "TOP (image right = model +y, its back; down = +x, its left)"}[views[k]] + "   " + title,
           fill=(255, 255, 255))
    for bn, (a, b) in bones.items():
        def px(p):
            if views[k] == "top":
                return (ox + (p[1] + span) / (2 * span) * w, 30 + (p[0] + span) / (2 * span) * h)
            u = p[0] if k == 0 else p[1]
            return (ox + (u + span) / (2 * span) * w, 30 + (2 * span - 0.05 - p[2]) / (2 * span) * h)
        d.line([px(a), px(b)], fill=(255, 140, 0), width=3)
        d.ellipse([px(a)[0] - 4, px(a)[1] - 4, px(a)[0] + 4, px(a)[1] + 4], fill=(255, 40, 0))
sheet.save(os.path.join(cache, name + ".png"))
print("wrote", os.path.join(cache, name + ".png"))
