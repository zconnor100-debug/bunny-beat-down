#!/usr/bin/env python3
"""Assemble the per-model renders from render_previews.py into one labelled sheet.

    python3 -I tools/env/make_preview_sheet.py [out.png]

Default output: assets/env/preview_sheet.png.  Each cell shows the model next to
the 1 m orange critter capsule; tall models get their base close-up as an inset.
Labels: id, category, height, triangles and GLB size.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
FRAMES = Path("/tmp/bbd-envpreview")
CELL, LABEL, COLS = 320, 34, 6


def font(size: int):
    for name in ("DejaVuSans.ttf", "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return ImageFont.load_default()


def main() -> None:
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "assets" / "env" / "preview_sheet.png"
    manifest = json.loads((ROOT / "assets" / "env" / "manifest.json").read_text())
    rows = (len(manifest) + COLS - 1) // COLS
    title_h = 40
    sheet = Image.new("RGB", (COLS * CELL, title_h + rows * (CELL + LABEL)), (24, 26, 24))
    d = ImageDraw.Draw(sheet)
    f1, f2, ft = font(15), font(12), font(20)
    d.text((10, 9), "Bunny Beat Down - environment kit (orange capsule = 1 m critter; inset = critter's-eye view of the base)",
           fill=(235, 235, 220), font=ft)
    for n, a in enumerate(manifest):
        x, y = (n % COLS) * CELL, title_h + (n // COLS) * (CELL + LABEL)
        frame = FRAMES / f"{a['id']}.png"
        if frame.exists():
            im = Image.open(frame).convert("RGB")
            im.thumbnail((CELL, CELL))
            sheet.paste(im, (x, y))
            base = FRAMES / f"{a['id']}_base.png"
            if base.exists():
                inset = Image.open(base).convert("RGB")
                inset.thumbnail((CELL * 2 // 5, CELL * 2 // 5))
                sheet.paste(inset, (x + 4, y + CELL - inset.size[1] - 4))
                d.rectangle([x + 4, y + CELL - inset.size[1] - 4, x + 4 + inset.size[0], y + CELL - 4],
                            outline=(255, 200, 60), width=2)
        else:
            d.text((x + 10, y + 10), "no render", fill=(255, 90, 90), font=f1)
        glb = ROOT / a["file"]
        mb = glb.stat().st_size / 1e6 if glb.exists() else 0
        d.text((x + 6, y + CELL + 2), f"{a['id']}  ({a['category']})", fill=(255, 255, 255), font=f1)
        d.text((x + 6, y + CELL + 19),
               f"h {a['height_m']} m  r {a['footprint_radius_m']} m  {a.get('tris', 0)} tris  {mb:.1f} MB",
               fill=(190, 200, 180), font=f2)
    # full-colour PNG: a 256-colour palette visibly shifted material colours
    sheet.save(out, optimize=True)
    print("wrote", out, f"{out.stat().st_size / 1e6:.1f} MB")


if __name__ == "__main__":
    main()
