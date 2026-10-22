#!/usr/bin/env python3
"""Draw the Audio Review launcher icon: the game icon (Bun) with a speaker badge.

    python3 tools/audio/make_review_icon.py      # writes tools/audio/review_icon.png
"""
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
OUT = Path(__file__).with_name("review_icon.png")
SIZE = 512


def main() -> None:
    base = Image.open(ROOT / "icon.png").convert("RGBA").resize((SIZE, SIZE), Image.LANCZOS)
    s = 4                                   # supersample the badge for smooth edges
    badge = Image.new("RGBA", (SIZE * s, SIZE * s), (0, 0, 0, 0))
    d = ImageDraw.Draw(badge)
    cx, cy, r = int(SIZE * 0.74) * s, int(SIZE * 0.74) * s, int(SIZE * 0.24) * s
    d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=(43, 33, 24, 255), outline=(232, 122, 23, 255), width=10 * s)
    cream = (255, 244, 224, 255)
    # speaker: box + cone
    u = r / 10
    d.rectangle((cx - 6.2 * u, cy - 2.2 * u, cx - 3.4 * u, cy + 2.2 * u), fill=cream)
    d.polygon([(cx - 3.4 * u, cy - 2.2 * u), (cx + 0.6 * u, cy - 5.6 * u), (cx + 0.6 * u, cy + 5.6 * u), (cx - 3.4 * u, cy + 2.2 * u)], fill=cream)
    # sound waves
    for i, rr in enumerate((3.4, 5.6, 7.8)):
        box = (cx + 0.6 * u - rr * u, cy - rr * u, cx + 0.6 * u + rr * u, cy + rr * u)
        d.arc(box, start=-48, end=48, fill=(232, 122, 23, 255) if i == 2 else cream, width=int(1.1 * u))
    badge = badge.resize((SIZE, SIZE), Image.LANCZOS)
    Image.alpha_composite(base, badge).save(OUT, optimize=True)
    print(f"wrote {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
