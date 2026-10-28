"""Say any line in a rogue's own voice (for trailers): the rogue's Maya1 design
from maya_voices.json, spoken exactly as build_voices_maya.py speaks the
game's clips (its anchors, the best of several takes heard back, its accent,
pitch and tempo).

    HF_HOME=~/ai/hf-cache ~/ai/venvs/chatterbox/bin/python tools/voices/say.py OUT_DIR "Rogue|id|line" ...

writes OUT_DIR/<id>.wav (24 kHz mono) for each. The old Kokoro voices
(cast_voices.json, build_voices.py) are still there with --kokoro:

    HF_HOME=~/ai/hf-cache ~/ai/venvs/tts/bin/python tools/voices/say.py --kokoro OUT_DIR "Rogue|id|line" ...

A line the game already says (its key, as Cast.say makes them: "gspot.1"),
cut from the rogue's voice bank exactly as the game plays it (its word clips
one after another, nothing spoken anew; needs ffmpeg):

    python3 tools/voices/say.py --from-bank OUT_DIR "Rogue|id|gspot.1" ...
"""
from __future__ import annotations

import json
import subprocess
import sys
import time
import wave
from pathlib import Path

HERE = Path(__file__).resolve().parent
BANK = HERE.parents[1] / "assets" / "voices"


def from_bank(out: Path, specs: list) -> None:
    bank = json.loads((BANK / "voices.json").read_text())
    for spec in specs:
        name, cid, key = spec.split("|", 2)
        r = bank["rogues"][name]
        pcm = b""
        for step in bank["plans"][key]:
            if step[0] == "t":
                start, length, *f = r["clips"]["t%d" % step[1]]
                pcm += subprocess.run(["ffmpeg", "-v", "error", "-ss", str(start), "-t", str(length), "-i", str(BANK / (f[0] if f else r["file"])),
                                      "-ac", "1", "-ar", "24000", "-f", "s16le", "-"], capture_output=True, check=True).stdout
            elif step[0] == "pause":
                pcm += b"\0\0" * int(24000 * float(step[1]))
        with wave.open(str(out / f"{cid}.wav"), "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(24000)
            w.writeframes(pcm)
        print("CUT  %-14s %-16s %.2f s  %s" % (cid, name, len(pcm) / 48000, key), flush=True)


def kokoro(out: Path, specs: list) -> None:
    import soundfile as sf
    sys.path.insert(0, str(HERE))
    import build_voices as B
    designs = json.loads((HERE / "cast_voices.json").read_text())
    from kokoro import KPipeline  # (slow to import)
    pipes: dict = {}
    for spec in specs:
        name, cid, text = spec.split("|", 2)
        d = designs[name]
        if d["lang"] not in pipes:
            pipes[d["lang"]] = KPipeline(lang_code=d["lang"], repo_id="hexgrad/Kokoro-82M")
        x = B.Voice(pipes, d).say(B.L.spoken(text))
        sf.write(out / f"{cid}.wav", x, B.SR)
        print("SAID %-14s %-16s %.2f s  %s" % (cid, name, len(x) / B.SR, text), flush=True)


def maya(out: Path, specs: list) -> None:
    import soundfile as sf
    sys.path.insert(0, str(HERE))
    import build_voices as B
    import build_voices_maya as M
    designs = json.loads((HERE / "maya_voices.json").read_text())
    t0 = time.time()
    log = lambda s: print("[%5.0fs] %s" % (time.time() - t0, s), flush=True)
    m = M.Maya()
    for spec in specs:
        name, cid, text = spec.split("|", 2)
        x = M.render(m, name, designs[name], {cid: B.L.spoken(text)}, log)[cid]
        sf.write(out / f"{cid}.wav", x, M.SR)
        print("SAID %-14s %-16s %.2f s  %s" % (cid, name, len(x) / M.SR, text), flush=True)


def main() -> None:
    args = sys.argv[1:]
    how = kokoro if "--kokoro" in args else (from_bank if "--from-bank" in args else maya)
    args = [a for a in args if a not in ("--kokoro", "--from-bank")]
    out = Path(args[0])
    out.mkdir(parents=True, exist_ok=True)
    how(out, args[1:])


if __name__ == "__main__":
    main()
