#!/usr/bin/env python3
"""Draw the Game Notes launcher icon: the game icon (Bun) with a notepad badge.

    python3 tools/notes/make_notes_icon.py      # writes tools/notes/notes_icon.png
"""
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
OUT = Path(__file__).with_name("notes_icon.png")
SIZE = 512


def main() -> None:
    base = Image.open(ROOT / "icon.png").convert("RGBA").resize((SIZE, SIZE), Image.LANCZOS)
    s = 4                                   # supersample the badge for smooth edges
    badge = Image.new("RGBA", (SIZE * s, SIZE * s), (0, 0, 0, 0))
    d = ImageDraw.Draw(badge)
    cx, cy, r = int(SIZE * 0.74) * s, int(SIZE * 0.74) * s, int(SIZE * 0.24) * s
    d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=(43, 33, 24, 255), outline=(232, 122, 23, 255), width=10 * s)
    cream, carrot, ink = (255, 244, 224, 255), (232, 122, 23, 255), (95, 80, 63, 255)
    u = r / 10
    # notepad with ruled lines
    d.rounded_rectangle((cx - 5.2 * u, cy - 6.2 * u, cx + 3.6 * u, cy + 6.0 * u), radius=int(0.9 * u), fill=cream)
    for i in range(4):
        y = cy - 2.6 * u + i * 2.4 * u
        d.line((cx - 3.6 * u, y, cx + 2.0 * u, y), fill=ink, width=int(0.55 * u))
    # pencil (a carrot-orange one, of course) across the corner
    d.polygon([(cx + 0.6 * u, cy + 3.8 * u), (cx + 6.4 * u, cy - 2.0 * u), (cx + 7.9 * u, cy - 0.5 * u),
               (cx + 2.1 * u, cy + 5.3 * u)], fill=carrot)
    d.polygon([(cx + 0.6 * u, cy + 3.8 * u), (cx + 2.1 * u, cy + 5.3 * u), (cx - 0.3 * u, cy + 6.2 * u)], fill=cream)
    badge = badge.resize((SIZE, SIZE), Image.LANCZOS)
    Image.alpha_composite(base, badge).save(OUT, optimize=True)
    print(f"wrote {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
