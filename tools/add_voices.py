#!/usr/bin/env python3
"""Lay rogues' voices into a finished trailer: each clip at the second its
speech bubble comes up, the trailer's own sound ducked a little under them
(so a line isn't lost under the gunfire). The picture is copied as it is.

The trailers cut before the rogues had voices (the island trailer, the
30-second trailer and its phone cut) only showed their lines; their clips
come from tools/voices/say.py (the game's own clip with --from-bank, or a
line spoken anew in the rogue's voice):

    python3 tools/voices/say.py --from-bank /tmp/v "Sly|sly_dont|p.sneak.spot.2|you=Bun"
    python3 tools/add_voices.py docs/trailer.mp4 /tmp/trailer.mp4 /tmp/v/sly_dont.wav@6.22

Needs ffmpeg.
"""
import argparse
import pathlib
import subprocess

VOICE_GAIN = 1.5     # each line, over its clip's own level
DUCK = "threshold=0.03:ratio=3:attack=15:release=300"   # the trailer's sound, while a line is said


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("video", type=pathlib.Path)
    ap.add_argument("out", type=pathlib.Path)
    ap.add_argument("clips", nargs="+", help="voice.wav@seconds")
    args = ap.parse_args()
    inputs = ["-i", str(args.video)]
    mix = ""
    for k, spec in enumerate(args.clips):
        wav, at = spec.rsplit("@", 1)
        inputs += ["-i", wav]
        ms = int(float(at) * 1000)
        mix += f"[{k + 1}:a]aresample=48000,aformat=channel_layouts=stereo,adelay={ms}|{ms},volume={VOICE_GAIN}[v{k}];"
    n = len(args.clips)
    mix += "".join(f"[v{k}]" for k in range(n)) + f"amix=inputs={n}:duration=longest:normalize=0,asplit=2[vox][key];"
    mix += f"[0:a][key]sidechaincompress={DUCK}[bed];"
    mix += "[bed][vox]amix=inputs=2:duration=first:normalize=0,alimiter=limit=0.89:level=false[a]"
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", *inputs, "-filter_complex", mix,
                    "-map", "0:v", "-map", "[a]", "-c:v", "copy", "-c:a", "aac", "-b:a", "160k",
                    "-movflags", "+faststart", str(args.out)], check=True)
    print(f"{args.out}: {n} lines, {args.out.stat().st_size / 1e6:.1f} MB")


if __name__ == "__main__":
    main()
