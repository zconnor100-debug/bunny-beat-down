#!/usr/bin/env python3
"""Put boss_build.py's renders on a measuring grid (needs Pillow).

    python3 tools/characters/boss_grid.py <cache dir> grid|rig|poses [title]

grid / rig: <name>_front.png + <name>_side.png side by side with a 0.05 grid
(labelled in the normalized model's units) and, for rig, its bones drawn on
top (<name>_bones.json) -> <name>.png. poses: pose_*.png in a row -> poses.png.
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
ims = [Image.open(os.path.join(cache, name + "_front.png")).convert("RGB"),
       Image.open(os.path.join(cache, name + "_side.png")).convert("RGB")]
bones = json.load(open(os.path.join(cache, name + "_bones.json")))
w, h = ims[0].size
sheet = Image.new("RGB", (w * 2 + 10, h + 30), (40, 40, 40))
d = ImageDraw.Draw(sheet)
for k, im in enumerate(ims):
    ox = k * (w + 10)
    sheet.paste(im, (ox, 30))
    # the views span x in [-0.6, 0.6] (front: model x; side: model y) and z in [-0.05, 1.15]
    for i in range(-12, 13):
        x = ox + int((i * 0.05 + 0.6) / 1.2 * w)
        col = (200, 60, 60) if i == 0 else ((90, 90, 200) if i % 2 == 0 else (190, 190, 215))
        d.line([(x, 30), (x, 30 + h)], fill=col, width=1)
        if i % 2 == 0:
            d.text((x + 2, 32), "%.1f" % (i * 0.05), fill=(30, 30, 160))
    for j in range(0, 24):
        z = j * 0.05
        y = 30 + int((1.15 - z) / 1.2 * h)
        col = (200, 60, 60) if j == 0 else ((90, 90, 200) if j % 2 == 0 else (190, 190, 215))
        d.line([(ox, y), (ox + w, y)], fill=col, width=1)
        if j % 2 == 0:
            d.text((ox + 3, y - 12), "%.2f" % z, fill=(30, 30, 160))
    d.text((ox + 8, 8), ("FRONT (image right = model +x, its left)" if k == 0 else
                         "SIDE from +x (image right = model +y, its back)") + "   " + title, fill=(255, 255, 255))
    for bn, (a, b) in bones.items():
        def px(p):
            u = p[0] if k == 0 else p[1]
            return (ox + (u + 0.6) / 1.2 * w, 30 + (1.15 - p[2]) / 1.2 * h)
        d.line([px(a), px(b)], fill=(255, 140, 0), width=3)
        d.ellipse([px(a)[0] - 4, px(a)[1] - 4, px(a)[0] + 4, px(a)[1] + 4], fill=(255, 40, 0))
sheet.save(os.path.join(cache, name + ".png"))
print("wrote", os.path.join(cache, name + ".png"))
