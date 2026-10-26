"""Say any line in a rogue's own voice (for trailers): the rogue's design from
cast_voices.json, spoken exactly as build_voices.py speaks the game's clips.

    HF_HOME=~/ai/hf-cache ~/ai/venvs/tts/bin/python tools/voices/say.py OUT_DIR "Rogue|id|line" ...

writes OUT_DIR/<id>.wav (24 kHz mono) for each.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import soundfile as sf

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import build_voices as B  # noqa: E402


def main() -> None:
    out = Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    designs = json.loads((HERE / "cast_voices.json").read_text())
    from kokoro import KPipeline  # (slow to import)
    pipes: dict = {}
    for spec in sys.argv[2:]:
        name, cid, text = spec.split("|", 2)
        d = designs[name]
        if d["lang"] not in pipes:
            pipes[d["lang"]] = KPipeline(lang_code=d["lang"], repo_id="hexgrad/Kokoro-82M")
        x = B.Voice(pipes, d).say(B.L.spoken(text))
        sf.write(out / f"{cid}.wav", x, B.SR)
        print("SAID %-14s %-16s %.2f s  %s" % (cid, name, len(x) / B.SR, text), flush=True)


if __name__ == "__main__":
    main()
