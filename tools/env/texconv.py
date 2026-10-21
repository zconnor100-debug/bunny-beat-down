#!/usr/bin/env python3
"""Texture conversion jobs for the environment pipeline (system Python + Pillow).

    python3 -I tools/env/texconv.py jobs.json

jobs.json is a list of objects:

    {"src": "in.jpg", "dst": "out.png", "max": 1024,
     "mode": "rgb" | "rgba" | "gray" | "orm",  # channel layout of the output
     "rough_src"/"ao_src"/"metallic": ...,  # inputs for mode "orm" (packed AO/rough/metal)
     "alpha_src": "mask.png",               # optional: separate alpha mask to merge in
     "alpha_channel": "L" | "A",            # mask = its luminance (default) or its alpha
     "bleed": true,                         # optional: push-pull colour into transparent texels
     "quality": 88,                         # JPEG quality
     "crop": [u0, v0, u1, v1],              # optional UV-space crop (atlas -> one object's region)
     "size": [w, h]}                        # optional exact output size instead of "max"

The output format follows dst's extension (.jpg -> baseline JPEG, .png -> PNG).
Images are downscaled with Lanczos so the longest side is <= max; they are never
upscaled.  16-bit PNGs (Poly Haven ships some) are reduced to 8 bit correctly.

Alpha bleeding matters for cut-out foliage: without it, the colour of fully
transparent texels (often black or white) leaks into mip-maps and draws dark or
light halos around every leaf and grass blade in the game.
"""
from __future__ import annotations

import json
import math
import sys
from pathlib import Path

from PIL import Image, ImageMath

Image.MAX_IMAGE_PIXELS = 16384 * 16384  # sources are at most 8K


def to_8bit(im: Image.Image) -> Image.Image:
    """Convert any Pillow mode to 8 bit per channel without clipping 16-bit data."""
    if im.mode in ("I;16", "I;16B", "I;16L", "I"):
        im = im.convert("I").point(lambda v: v * (1.0 / 256.0)).convert("L")
    elif im.mode == "F":
        im = im.convert("L")
    elif im.mode == "P":
        im = im.convert("RGBA")
    return im


def fit(im: Image.Image, max_side: int) -> Image.Image:
    w, h = im.size
    if max(w, h) <= max_side:
        return im
    s = max_side / float(max(w, h))
    return im.resize((max(1, round(w * s)), max(1, round(h * s))), Image.LANCZOS)


def snap_pot(im: Image.Image, max_side: int) -> Image.Image:
    """Resample to power-of-two sides (e.g. after an atlas crop, 2048x1862 -> 2048x2048).

    GPU block compression (BCn/ETC, used by Godot's VRAM-compressed import) needs
    sides that are multiples of 4, and mip chains are cleanest on powers of two.
    The UVs address the whole image, so a slight resample does not move anything.
    """
    def pot(n: int) -> int:
        return min(max_side, 1 << max(2, round(math.log2(n))))
    w, h = im.size
    size = (pot(w), pot(h))
    return im if size == (w, h) else im.resize(size, Image.LANCZOS)


def bleed(rgba: Image.Image, threshold: int = 16) -> Image.Image:
    """Fill RGB of transparent texels with the colour of nearby opaque texels (push-pull)."""
    r, g, b, a = rgba.split()
    mask = a.point(lambda v: 255 if v > threshold else 0)
    rgb = Image.merge("RGB", (r, g, b))
    zero = Image.new("RGB", rgb.size, (0, 0, 0))
    premul = Image.composite(rgb, zero, mask)

    # Build a pyramid of (premultiplied colour, coverage) by 2x box filtering.
    levels = [(premul, mask)]
    while min(levels[-1][0].size) > 2:
        p, w = levels[-1]
        size = (max(1, p.size[0] // 2), max(1, p.size[1] // 2))
        levels.append((p.resize(size, Image.BOX), w.resize(size, Image.BOX)))

    def normalized(p: Image.Image, w: Image.Image) -> Image.Image:
        chans = [ImageMath.eval("convert(float(c) * 255.0 / max(float(w), 1.0), 'L')", c=c, w=w)
                 for c in p.split()]
        return Image.merge("RGB", chans)

    # Pull: start from the coarsest level and fill holes level by level.
    p, w = levels[-1]
    filled = normalized(p, w)
    for p, w in reversed(levels[:-1]):
        up = filled.resize(p.size, Image.BILINEAR)
        has = w.point(lambda v: 255 if v > 0 else 0)
        filled = Image.composite(normalized(p, w), up, has)
    out = Image.composite(rgb, filled, mask)
    out.putalpha(a)
    return out


def pack_orm(job: dict) -> Image.Image:
    """glTF occlusion/roughness/metallic texture: R = AO, G = roughness, B = metallic."""
    rough = to_8bit(Image.open(job["rough_src"])).convert("L")
    ao = to_8bit(Image.open(job["ao_src"])).convert("L").resize(rough.size) if job.get("ao_src") \
        else Image.new("L", rough.size, 255)
    metal = Image.new("L", rough.size, int(job.get("metallic", 0)))
    return Image.merge("RGB", (ao, rough, metal))


def run(job: dict) -> None:
    src, dst = Path(job.get("src", "")), Path(job["dst"])
    mode = job.get("mode", "rgb")
    im = pack_orm(job) if mode == "orm" else to_8bit(Image.open(src))
    im.load()
    if job.get("crop"):
        # UV-space rectangle [u0, v0, u1, v1] (v up, as in glTF/Blender UVs)
        u0, v0, u1, v1 = job["crop"]
        w, h = im.size
        im = im.crop((round(u0 * w), round((1 - v1) * h), round(u1 * w), round((1 - v0) * h)))
    if mode == "orm":
        pass
    elif mode == "rgba":
        im = im.convert("RGBA")
        if job.get("alpha_src"):
            mask = to_8bit(Image.open(job["alpha_src"]))
            if job.get("alpha_channel") == "A" and mask.mode in ("RGBA", "LA"):
                mask = mask.split()[-1]
            mask = mask.convert("L")
            if mask.size != im.size:
                mask = mask.resize(im.size, Image.LANCZOS)
            im.putalpha(mask)
    elif mode == "gray":
        im = im.convert("L")
    else:
        im = im.convert("RGB")
    if job.get("size"):  # exact size (may change aspect, e.g. to match a 1:2 bark UV layout)
        im = im.resize(tuple(job["size"]), Image.LANCZOS)
    else:
        im = fit(im, int(job.get("max", 2048)))
        im = snap_pot(im, int(job.get("max", 2048)))
    if mode == "rgba" and job.get("bleed", True):
        im = bleed(im)
    dst.parent.mkdir(parents=True, exist_ok=True)
    if dst.suffix.lower() in (".jpg", ".jpeg"):
        if im.mode == "RGBA":
            im = im.convert("RGB")
        im.save(dst, "JPEG", quality=int(job.get("quality", 88)), optimize=True)
    else:
        im.save(dst, "PNG", optimize=True)


def main() -> None:
    jobs = json.loads(Path(sys.argv[1]).read_text())
    for job in jobs:
        run(job)
        print("texconv", Path(job["dst"]).name, flush=True)


if __name__ == "__main__":
    main()
