#!/usr/bin/env python3
"""Turn a Godot Movie Maker PNG sequence into a README-sized animated GIF.

    godot --path . --write-movie /tmp/frames/f.png --fixed-fps 30 -s tests/capture_showcase.gd
    python3 tools/make_gif.py /tmp/frames docs/screenshots/gameplay.gif --width 720 --step 2

--step 2 keeps every other frame (30 fps -> 15 fps). A shared palette built from a
sample of frames keeps colours stable between frames (no flicker) and the file small.
"""
import argparse
import pathlib

from PIL import Image


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("frames", type=pathlib.Path)
    ap.add_argument("out", type=pathlib.Path)
    ap.add_argument("--width", type=int, default=720)
    ap.add_argument("--step", type=int, default=2)
    ap.add_argument("--start", type=int, default=0)
    ap.add_argument("--end", type=int, default=-1)
    ap.add_argument("--fps", type=float, default=30.0)
    ap.add_argument("--crop", type=float, nargs=4, metavar=("L", "T", "R", "B"),
                    help="crop box as fractions of the frame, e.g. 0.15 0.2 0.85 0.9")
    ap.add_argument("--dither", action="store_true", help="Floyd-Steinberg dither (bigger file)")
    args = ap.parse_args()

    paths = sorted(args.frames.glob("*.png"))[args.start:args.end if args.end > 0 else None:args.step]
    if not paths:
        raise SystemExit("no frames found")
    frames = []
    for p in paths:
        im = Image.open(p).convert("RGB")
        if args.crop:
            l, t, r, b = args.crop
            im = im.crop((int(l * im.width), int(t * im.height), int(r * im.width), int(b * im.height)))
        h = round(im.height * args.width / im.width)
        frames.append(im.resize((args.width, h), Image.LANCZOS))

    # one palette for the whole clip, sampled across it
    sample = Image.new("RGB", (args.width, frames[0].height * 4))
    for i, k in enumerate(range(0, len(frames), max(1, len(frames) // 4))):
        if i < 4:
            sample.paste(frames[k], (0, i * frames[0].height))
    palette = sample.quantize(colors=255, method=Image.Quantize.MEDIANCUT)
    dither = Image.Dither.FLOYDSTEINBERG if args.dither else Image.Dither.NONE
    quantized = [f.quantize(palette=palette, dither=dither) for f in frames]

    duration = int(1000 * args.step / args.fps)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    quantized[0].save(args.out, save_all=True, append_images=quantized[1:], duration=duration,
                      loop=0, optimize=True, disposal=1)
    print(f"wrote {args.out} ({len(quantized)} frames, {args.out.stat().st_size / 1e6:.1f} MB)")


if __name__ == "__main__":
    main()
