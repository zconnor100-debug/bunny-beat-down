#!/usr/bin/env python3
"""Cut the 30-second phone reel from tests/trailer_reel_stage.gd's recordings.

Each map is recorded on its own (Movie Maker, every frame, the game's own
sound with its music muted), and the stage prints where each shot starts and
ends (SHOT name first_frame end_frame) in the log. This lays the shots out in
EDIT order, takes each one's own game sound with it, puts one music track
under the lot and makes:

    <out>.mp4        1080x1920, sharp (for sharing anywhere)
    <out>_text.mp4   720x1280, about 3 MB (iMessage, RCS, WhatsApp)
    <out>_mms.mp4    540x960, under 1 MB (a plain MMS text on any phone)

    # record each map into its own folder (phone frame: see capture_trailer.gd)
    godot --path . --write-movie /tmp/reel/island/f.png --fixed-fps 30 \\
          -s tests/capture_trailer.gd -- reel island > /tmp/reel/island/log.txt
    (the same for cage and toybox)
    python3 tools/make_reel.py /tmp/reel docs/trailer_phone

Needs ffmpeg.
"""
import argparse
import os
import pathlib
import re
import shutil
import subprocess
import tempfile
import wave

FPS = 30
MUSIC = "assets/audio/music/match_run_amok.mp3"   # Run Amok, Kevin MacLeod (incompetech.com, CC BY 4.0)
# (map, shot, from s, to s): the cut, in order
EDIT = [
    ("island", "drop", 0.0, 2.9),
    ("island", "brawl", 0.0, 3.2),
    ("island", "hero", 0.0, 2.1),
    ("island", "rocket", 0.25, 2.7),
    ("cage", "mutations", 0.0, 2.6),
    ("cage", "cage_brawl", 0.0, 2.5),
    ("toybox", "toybox", 0.0, 2.6),
    ("cage", "nemesis", 0.0, 2.6),
    ("island", "rewind_creep", 0.0, 1.0),
    ("island", "rewind_freeze", 0.0, 1.0),
    ("island", "rewind_turn", 0.0, 3.0),
    ("island", "card", 0.0, 3.8),
]


def shots_of(folder: pathlib.Path) -> dict:
    log = (folder / "log.txt").read_text(errors="replace")
    end = int(re.search(r"REEL_END (\d+)", log).group(1))
    last = max(int(p.stem[1:]) for p in folder.glob("f*.png"))
    off = last - end   # Movie Maker's file numbers against the engine's frame count
    return {m.group(1): (int(m.group(2)) + off, int(m.group(3)) + off) for m in re.finditer(r"SHOT (\S+) (\d+) (\d+)", log)}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("reel", type=pathlib.Path, help="folder holding island/ cage/ toybox/ recordings")
    ap.add_argument("out", type=pathlib.Path, help="output path without extension")
    args = ap.parse_args()
    root = pathlib.Path(__file__).resolve().parent.parent
    shots = {m: shots_of(args.reel / m) for m in {e[0] for e in EDIT}}
    tmp = pathlib.Path(tempfile.mkdtemp(prefix="reel_"))
    try:
        # the frames, in edit order (links), and each shot's own sound
        n = 0
        pcm = bytearray()
        params = None
        for m, shot, a, b in EDIT:
            first, end = shots[m][shot]
            lo = first + round(a * FPS)
            hi = min(end, first + round(b * FPS))
            for i in range(lo, hi):
                os.symlink(args.reel / m / f"f{i:08d}.png", tmp / f"c{n:06d}.png")
                n += 1
            with wave.open(str(args.reel / m / "f.wav")) as w:
                params = params or w.getparams()
                per = w.getframerate() // FPS
                w.setpos(lo * per)
                pcm += w.readframes((hi - lo) * per)
        seconds = n / FPS
        with wave.open(str(tmp / "sfx.wav"), "wb") as w:
            w.setparams(params)
            w.writeframes(bytes(pcm))
        mix = (f"[1:a]volume=0.9[s];[2:a]atrim=0:{seconds:.3f},volume=0.55,afade=t=out:st={seconds - 1.5:.2f}:d=1.5[m];"
               f"[s][m]amix=inputs=2:duration=first:normalize=0,afade=t=in:d=0.2,"
               f"loudnorm=I=-14:TP=-1.5:LRA=11,aresample=48000,alimiter=limit=0.7:level=false[a]")
        master = args.out.with_suffix(".mp4")
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-framerate", str(FPS), "-i", str(tmp / "c%06d.png"),
                        "-i", str(tmp / "sfx.wav"), "-i", str(root / MUSIC), "-filter_complex", mix,
                        "-map", "0:v", "-map", "[a]", "-vf", "scale=1080:1920:flags=lanczos,format=yuv420p",
                        "-c:v", "libx264", "-preset", "slow", "-crf", "23", "-c:a", "aac", "-b:a", "160k",
                        "-movflags", "+faststart", str(master)], check=True)
        print(f"{master}: {seconds:.1f} s, {master.stat().st_size / 1e6:.1f} MB")
        # smaller cuts for texting, two-pass at a set bitrate so they land on size
        for suffix, size, vk, ak in [("_text", "720:1280", 700, 96), ("_mms", "540:960", 190, 48)]:
            out = args.out.parent / f"{args.out.name}{suffix}.mp4"
            common = ["-vf", f"scale={size}:flags=lanczos,format=yuv420p", "-c:v", "libx264", "-preset", "slow",
                      "-b:v", f"{vk}k", "-maxrate", f"{int(vk * 1.4)}k", "-bufsize", f"{vk * 2}k"]
            log = str(tmp / f"pass{suffix}")
            subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(master), *common, "-pass", "1",
                            "-passlogfile", log, "-an", "-f", "mp4", os.devnull], check=True)
            subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(master), *common, "-pass", "2",
                            "-passlogfile", log, "-c:a", "aac", "-b:a", f"{ak}k", "-ac", "1" if ak < 64 else "2",
                            "-movflags", "+faststart", str(out)], check=True)
            print(f"{out}: {out.stat().st_size / 1e6:.2f} MB")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    main()
