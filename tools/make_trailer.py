#!/usr/bin/env python3
"""Turn the Movie Maker recording of tests/capture_trailer.gd into the trailer
MP4 (with the game's own sound) and, optionally, a short README GIF.

    godot --path . --windowed --resolution 1920x1080 --write-movie /tmp/movie/f.png \\
          --fixed-fps 30 -s tests/capture_trailer.gd > /tmp/movie/log.txt
    python3 tools/make_trailer.py /tmp/movie docs/trailer.mp4 \\
          --gif docs/screenshots/trailer.gif --gif-from 4 --gif-to 21

The recording starts with the loading screen and the stage quits right after
the end card, so the trailer is the last N frames, N being the length the stage
prints on its TRAILER_END line (log.txt in the frames folder). Needs ffmpeg.
"""
import argparse
import pathlib
import re
import subprocess

FPS = 30


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("frames", type=pathlib.Path, help="Movie Maker folder (f########.png, f.wav, log.txt)")
    ap.add_argument("out", type=pathlib.Path)
    ap.add_argument("--gif", type=pathlib.Path)
    ap.add_argument("--gif-from", type=float, default=4.0, help="seconds into the trailer")
    ap.add_argument("--gif-to", type=float, default=21.0)
    ap.add_argument("--gif-width", type=int, default=480)
    ap.add_argument("--gif-fps", type=int, default=12)
    ap.add_argument("--gif-colors", type=int, default=128)
    ap.add_argument("--crf", type=int, default=26, help="x264 quality (lower = bigger, sharper)")
    args = ap.parse_args()

    log = (args.frames / "log.txt").read_text(errors="replace")
    seconds = float(re.search(r"TRAILER_END .*\(([\d.]+) s\)", log).group(1))
    frames = round(seconds * FPS)
    last = max(int(p.stem[1:]) for p in args.frames.glob("f*.png"))
    start = last - frames
    pattern = str(args.frames / "f%08d.png")
    # 16:9, 1080p, whatever size the window was
    video = "crop='min(iw,ih*16/9)':'min(ih,iw*9/16)',scale=1920:1080:flags=lanczos,format=yuv420p"
    audio = f"afade=t=in:d=0.4,afade=t=out:st={seconds - 1.2:.2f}:d=1.2,loudnorm=I=-14:TP=-1.5:LRA=11,aresample=48000,alimiter=limit=0.7:level=false"  # (AAC overshoots transients ~2 dB)
    cmd = ["ffmpeg", "-y", "-loglevel", "error",
           "-framerate", str(FPS), "-start_number", str(start), "-i", pattern,
           "-ss", f"{start / FPS:.3f}", "-t", f"{seconds:.3f}", "-i", str(args.frames / "f.wav"),
           "-frames:v", str(frames), "-vf", video, "-af", audio,
           "-c:v", "libx264", "-preset", "slow", "-crf", str(args.crf),
           "-c:a", "aac", "-b:a", "160k", "-movflags", "+faststart", "-shortest", str(args.out)]
    subprocess.run(cmd, check=True)
    print(f"{args.out}: {seconds:.1f} s, {args.out.stat().st_size / 1e6:.1f} MB")

    if args.gif:
        a = start + int(args.gif_from * FPS)
        n = int((args.gif_to - args.gif_from) * FPS)
        gif = (f"crop='min(iw,ih*16/9)':'min(ih,iw*9/16)',fps={args.gif_fps},scale={args.gif_width}:-2:flags=lanczos,"
               f"split[a][b];[a]palettegen=max_colors={args.gif_colors}:stats_mode=diff[p];"
               "[b][p]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle")
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-framerate", str(FPS), "-start_number", str(a),
                        "-i", pattern, "-t", f"{n / FPS:.3f}", "-filter_complex", gif, str(args.gif)], check=True)
        print(f"{args.gif}: {args.gif_to - args.gif_from:.1f} s, {args.gif.stat().st_size / 1e6:.1f} MB")


if __name__ == "__main__":
    main()
