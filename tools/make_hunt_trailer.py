#!/usr/bin/env python3
"""Cut "The Hunt", the phone trailer, from tests/trailer_hunt_stage.gd's recordings
(or, with --cut arsenal, "Your Arsenal" from tests/trailer_arsenal_stage.gd's).

Like tools/make_reel.py (each map recorded on its own, the stage printing
SHOT name first_frame end_frame), plus the hunting party's lines: the stage
prints LINE <id> <frame> when a rogue speaks (its speech bubble), and each
<id>.wav (tools/voices/say.py, in that rogue's own voice) is laid in at that
moment of the cut. Makes <out>_master.mp4 and <out>.mp4 (1080p, under 16 MB).

    # record each map at 1080x1920 (temporary override.cfg, as for the reel)
    godot --path . --write-movie /tmp/hunt/island/f.png --fixed-fps 30 \\
          -s tests/capture_trailer.gd -- hunt island > /tmp/hunt/island/log.txt
    (the same for cage and toybox)
    HF_HOME=~/ai/hf-cache ~/ai/venvs/chatterbox/bin/python tools/voices/say.py /tmp/hunt/lines "Buck Toothington|tally|Tally-ho! ..." ...
    python3 tools/make_hunt_trailer.py /tmp/hunt /tmp/hunt/lines docs/trailer_hunt_phone

"Your Arsenal" is 16:9 (viewport 1920x1080, window 1280x720 in the temporary
override.cfg), one recording on the island ("arsenal island"); its gang shout
lines the game already has, cut from their voice banks:

    python3 tools/voices/say.py --from-bank /tmp/arsenal/lines "Rocco|gspot|gspot.1" "Bog Boss|grush|grush.2"
    python3 tools/make_hunt_trailer.py --cut arsenal /tmp/arsenal /tmp/arsenal/lines docs/trailer_arsenal

Recorded at 1080x1920 instead (the tall override.cfg, as for The Hunt) the
stage frames every shot for a phone, and the same cut makes the phone one:

    python3 tools/make_hunt_trailer.py --cut arsenal /tmp/arsenal_tall /tmp/arsenal/lines docs/trailer_arsenal_phone

Needs ffmpeg.
"""
import argparse
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile
import wave

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import make_reel as R  # noqa: E402

FPS = R.FPS
MUSIC = "assets/audio/music/match_bushwick_tarantella.mp3"   # Bushwick Tarantella, Kevin MacLeod (incompetech.com, CC BY 4.0)
ARSENAL_MUSIC = "assets/audio/music/cage_voxel_revolution.mp3"   # Voxel Revolution, Kevin MacLeod (incompetech.com, CC BY 4.0)
# (map, shot, from s, to s): the cut, in order
EDIT = [
    ("island", "island_crane", 0.0, 3.0),
    ("island", "reveal", 0.0, 2.8),
    ("island", "chase", 0.0, 3.6),
    ("island", "rocket", 0.0, 3.25),
    ("cage", "cage_crane", 0.0, 4.0),
    ("cage", "cage_charge", 0.0, 3.3),
    ("toybox", "toy_crane", 0.0, 2.7),
    ("toybox", "train", 0.0, 3.0),
    ("toybox", "last", 0.0, 3.8),
    ("toybox", "card", 0.0, 3.8),
]
ARSENAL_EDIT = [
    ("island", "gang", 0.0, 3.2),
    ("island", "charge", 0.0, 2.4),
    ("island", "call", 0.0, 2.8),
    ("island", "rumbler", 0.0, 4.5),
    ("island", "lobber", 0.0, 3.8),
    ("island", "doppel", 0.0, 2.2),
    ("island", "fifty", 0.0, 3.4),
    ("island", "card", 0.0, 4.0),
]
CUTS = {"hunt": (EDIT, MUSIC), "arsenal": (ARSENAL_EDIT, ARSENAL_MUSIC)}


def lines_of(folder: pathlib.Path) -> list:
    """(id, frame file number) for each line spoken in a map's recording."""
    log = (folder / "log.txt").read_text(errors="replace")
    end = int(re.search(r"REEL_END (\d+)", log).group(1))
    last = max(int(p.stem[1:]) for p in folder.glob("f*.png"))
    off = last - end
    return [(m.group(1), int(m.group(2)) + off) for m in re.finditer(r"LINE (\S+) (\d+)", log)]


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--cut", choices=sorted(CUTS), default="hunt")
    ap.add_argument("rec", type=pathlib.Path, help="folder holding a folder of frames per map (island/ cage/ toybox/)")
    ap.add_argument("voices", type=pathlib.Path, help="folder of <line id>.wav (tools/voices/say.py)")
    ap.add_argument("out", type=pathlib.Path, help="output path without extension")
    args = ap.parse_args()
    edit, music = CUTS[args.cut]
    root = pathlib.Path(__file__).resolve().parent.parent
    maps = {e[0] for e in edit}
    shots = {m: R.shots_of(args.rec / m) for m in maps}
    spoken = {m: lines_of(args.rec / m) for m in maps}
    tmp = pathlib.Path(tempfile.mkdtemp(prefix="hunt_"))
    try:
        n = 0
        pcm = bytearray()
        params = None
        voices = []   # (wav, seconds into the cut)
        for m, shot, a, b in edit:
            first, end = shots[m][shot]
            lo = first + round(a * FPS)
            hi = min(end, first + round(b * FPS))
            for cid, frame in spoken[m]:
                if lo <= frame < hi and (args.voices / f"{cid}.wav").exists():
                    voices.append((args.voices / f"{cid}.wav", (n + frame - lo) / FPS))
            for i in range(lo, hi):
                os.symlink(args.rec / m / f"f{i:08d}.png", tmp / f"c{n:06d}.png")
                n += 1
            with wave.open(str(args.rec / m / "f.wav")) as w:
                params = params or w.getparams()
                per = w.getframerate() // FPS
                w.setpos(lo * per)
                pcm += w.readframes((hi - lo) * per)
        seconds = n / FPS
        with wave.open(str(tmp / "sfx.wav"), "wb") as w:
            w.setparams(params)
            w.writeframes(bytes(pcm))
        inputs = ["-framerate", str(FPS), "-i", str(tmp / "c%06d.png"), "-i", str(tmp / "sfx.wav"), "-i", str(root / music)]
        mix = f"[1:a]volume=0.8[s];[2:a]atrim=0:{seconds:.3f},volume=0.42,afade=t=out:st={seconds - 1.5:.2f}:d=1.5[m];"
        parts = "[s][m]"
        for k, (wav, at) in enumerate(voices):
            inputs += ["-i", str(wav)]
            ms = int(at * 1000)
            mix += f"[{3 + k}:a]aresample=48000,aformat=channel_layouts=stereo,adelay={ms}|{ms},volume=2.2[v{k}];"
            parts += f"[v{k}]"
        mix += (f"{parts}amix=inputs={2 + len(voices)}:duration=first:normalize=0,afade=t=in:d=0.2,"
                f"loudnorm=I=-14:TP=-1.5:LRA=11,aresample=48000,alimiter=limit=0.7:level=false[a]")
        size = R.png_size(tmp / "c000000.png")
        master = args.out.parent / f"{args.out.name}_master.mp4"
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", *inputs, "-filter_complex", mix,
                        "-map", "0:v", "-map", "[a]", "-vf", "format=yuv420p",
                        "-c:v", "libx264", "-preset", "slow", "-crf", "17", "-c:a", "aac", "-b:a", "192k",
                        "-movflags", "+faststart", str(master)], check=True)
        print(f"{master}: {size[0]}x{size[1]}, {seconds:.1f} s, {len(voices)} lines, {master.stat().st_size / 1e6:.1f} MB")
        for wav, at in voices:
            print(f"  {at:5.2f} s  {wav.stem}")
        out = args.out.with_suffix(".mp4")
        vk = int((15.2e6 * 8 / seconds - 160e3) / 1000)
        common = ["-c:v", "libx264", "-preset", "slow", "-b:v", f"{vk}k", "-maxrate", f"{int(vk * 1.5)}k",
                  "-bufsize", f"{vk * 2}k", "-pix_fmt", "yuv420p"]
        log = str(tmp / "pass")
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(master), *common, "-pass", "1",
                        "-passlogfile", log, "-an", "-f", "mp4", os.devnull], check=True)
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(master), *common, "-pass", "2",
                        "-passlogfile", log, "-c:a", "aac", "-b:a", "160k", "-movflags", "+faststart", str(out)], check=True)
        print(f"{out}: {size[0]}x{size[1]}, {out.stat().st_size / 1e6:.1f} MB")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    main()
