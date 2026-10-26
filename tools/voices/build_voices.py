"""Speak every rogue's lines in its own voice (Kokoro-82M, Apache-2.0).

    HF_HOME=~/ai/hf-cache ~/ai/venvs/tts/bin/python tools/voices/build_voices.py [--only "Sly,Nutsy"] [--audition DIR]

Reads tools/voices/lines.json (written by `godot --headless --path . -s
tests/export_lines.gd`) and tools/voices/cast_voices.json (each rogue's voice;
written here the first time from the casting rules below, then kept, so
voices stay put and can be tuned by hand), and writes

    assets/voices/<rogue>.ogg     every clip the rogue says, one after another
    assets/voices/voices.json     the plans (lines.py) and where each clip is

A rogue's voice: two Kokoro voice packs blended (a pack is a style vector per
phoneme count, so a weighted mean is a voice between the two), British packs
for the nobles; pitched for its kind of critter (a hamster squeaks, a frog
croaks) and paced for its personality (a hothead gabbles, the calm one takes
its time). Pitch is a resample (it also speeds the voice up), so Kokoro
speaks at tempo / pitch to land on the wanted pace.

--audition DIR writes a few lines per rogue as WAVs to listen to, instead.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
import sys
from fractions import Fraction
from pathlib import Path

import numpy as np
import soundfile as sf
from scipy.signal import resample_poly

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
OUT = ROOT / "assets" / "voices"
sys.path.insert(0, str(HERE))
import lines as L  # noqa: E402

SR = 24000
GAP = 0.15            # silence between clips in a rogue's file
NUM_MAX = 60          # scores read out up to here (RogueVoice.NUM_MAX)

# ---------------------------------------------------------------- casting
FEMALE = {"Vex", "Snickerdoodle", "Cottontail Kate", "Hazel", "Bushytail Betty", "Vixen Vera", "Foxy Roxy",
          "Ember", "Duchess", "Dumpster Dot", "Lady Garbage", "Lily Pad Lou", "Hopscotch", "Puddles",
          "Lodge Lady", "Nibbler", "Whisker Biscuit"}
# Kokoro's own grades for its English packs (VOICES.md). Only the high ones are
# used: the D and F packs sound robotic. The best men's packs are C+
# (American) and C (British); the women's go up to A.
GRADES = {"af_heart": "A", "af_bella": "A-", "af_nicole": "B-", "bf_emma": "B-", "af_aoede": "C+", "af_kore": "C+",
          "af_sarah": "C+", "am_fenrir": "C+", "am_michael": "C+", "am_puck": "C+", "bm_george": "C", "bm_fable": "C"}
# packs that suit each personality (American; nobles are British)
PACKS = {
    "hothead": {"m": ["am_fenrir", "am_puck"], "f": ["af_bella", "af_sarah", "af_heart"]},
    "sneak": {"m": ["am_michael", "am_fenrir"], "f": ["af_nicole", "af_kore"]},
    "showoff": {"m": ["am_puck", "am_fenrir"], "f": ["af_bella", "af_heart", "af_aoede"]},
    "grump": {"m": ["am_michael", "am_fenrir"], "f": ["af_kore", "af_sarah"]},
    "scaredy": {"m": ["am_puck", "am_michael"], "f": ["af_sarah", "af_nicole", "af_aoede"]},
    "prankster": {"m": ["am_puck", "am_michael"], "f": ["af_heart", "af_aoede", "af_sarah"]},
    "noble": {"m": ["bm_george", "bm_fable"], "f": ["bf_emma"]},
    "zen": {"m": ["am_michael", "am_puck"], "f": ["af_kore", "af_aoede", "af_nicole"]},
}
SPECIES_PITCH = {"hamster": 1.55, "squirrel": 1.4, "bandit_bunny": 1.15, "raccoon": 1.1, "fox": 1.0,
                 "beaver": 0.95, "frog": 0.82}
FEMALE_PITCH = 0.7    # (a female voice starts higher: it moves this share as far)
TEMPO = {"hothead": 1.12, "sneak": 0.92, "showoff": 1.08, "grump": 0.95, "scaredy": 1.16, "prankster": 1.1,
         "noble": 0.95, "zen": 0.86}


def _h(s: str, salt: str) -> float:
    """A steady 0..1 from a name (so a rogue's voice doesn't change between builds)."""
    return int(hashlib.sha1((salt + s).encode()).hexdigest()[:8], 16) / 0xFFFFFFFF


def cast(rogues: list[dict]) -> dict:
    """Each rogue's voice: packs, blend, pitch, tempo. Unique by construction:
    rogues sharing a personality and gender take the packs in turn."""
    out, seen = {}, {}
    for r in rogues:
        g = "f" if r["name"] in FEMALE else "m"
        pool = PACKS[r["voice"]][g]
        n = seen.get((r["voice"], g), 0)
        seen[(r["voice"], g)] = n + 1
        a = pool[n % len(pool)]
        b = pool[(n + 1 + int(_h(r["name"], "b") * (len(pool) - 1))) % len(pool)]
        if b == a:
            b = pool[(n + 1) % len(pool)]
        out[r["name"]] = {
            "packs": [a, b], "blend": round(0.55 + 0.3 * _h(r["name"], "w"), 2),
            "lang": "b" if a.startswith("b") else "a",
            "pitch": round((1.0 + (SPECIES_PITCH[r["species"]] - 1.0) * (FEMALE_PITCH if g == "f" else 1.0))
                           * (0.95 + 0.1 * _h(r["name"], "p")), 3),
            "tempo": round(TEMPO[r["voice"]] * (0.96 + 0.08 * _h(r["name"], "t")), 3),
        }
    return out


# ---------------------------------------------------------------- numbers
ONES = "zero one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen " \
       "seventeen eighteen nineteen".split()
TENS = "_ _ twenty thirty forty fifty sixty seventy eighty ninety".split()


def number_words(n: int) -> str:
    if n < 20:
        return ONES[n]
    return TENS[n // 10] + ("" if n % 10 == 0 else "-" + ONES[n % 10])


# ---------------------------------------------------------------- audio
class Voice:
    def __init__(self, pipes: dict, design: dict):
        p = pipes[design["lang"]]
        a, b = (p.load_voice(x) for x in design["packs"])
        self.pack = a * design["blend"] + b * (1.0 - design["blend"])
        self.pipe = p
        self.pitch = design["pitch"]
        self.speed = max(0.5, min(2.0, design["tempo"] / design["pitch"]))
        f = Fraction(1.0 / self.pitch).limit_denominator(200)
        self.up, self.down = f.numerator, f.denominator

    def say(self, text: str) -> np.ndarray:
        chunks = [np.asarray(audio, dtype=np.float32) for _, _, audio in self.pipe(text, voice=self.pack, speed=self.speed)
                  if audio is not None]
        x = np.concatenate(chunks) if chunks else np.zeros(1, np.float32)
        x = resample_poly(x, self.up, self.down).astype(np.float32)
        return finish(x)


def finish(x: np.ndarray) -> np.ndarray:
    """Trimmed to the voice (30 ms either side), at a steady loudness."""
    env = np.abs(x)
    k = int(SR * 0.01)
    if len(env) > k:
        env = np.convolve(env, np.ones(k) / k, mode="same")
    on = np.nonzero(env > 10 ** (-42 / 20))[0]
    if len(on):
        pad = int(SR * 0.03)
        x = x[max(0, on[0] - pad):min(len(x), on[-1] + pad)]
    rms = math.sqrt(float(np.mean(x ** 2))) or 1e-9
    x = x * (10 ** (-18 / 20) / rms)
    peak = float(np.max(np.abs(x))) or 1e-9
    if peak > 0.89:
        x = x * (0.89 / peak)
    fade = min(len(x) // 2, int(SR * 0.008))
    if fade > 0:
        ramp = np.linspace(0.0, 1.0, fade, dtype=np.float32)
        x[:fade] *= ramp
        x[-fade:] *= ramp[::-1]
    return x


def encode(audio: np.ndarray, path: Path) -> None:
    """Ogg Vorbis at speech quality, 16 kHz (libsndfile's own Vorbis encoder
    crashes on long writes, so ffmpeg's libvorbis does it)."""
    import subprocess
    import tempfile
    with tempfile.NamedTemporaryFile(suffix=".wav") as tmp:
        sf.write(tmp.name, audio, SR, subtype="PCM_16")
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp.name, "-ar", "16000", "-c:a", "libvorbis", "-b:a", "18k",
                        "-map_metadata", "-1", str(path)], check=True)


# ---------------------------------------------------------------- build
def slug(name: str) -> str:
    return re.sub(r"[^a-z0-9]+", "_", name.lower()).strip("_")


def rogue_clips(r: dict, templates: dict, plans: dict, seg_id: dict, you: list, rogues: list) -> dict:
    """What a rogue says: clip id -> text."""
    own = {k for k in templates if not k.startswith("p.") or k.startswith("p.%s." % r["voice"])}
    clips = {}
    for k in own:
        for part in plans[k]:
            if part[0] == "t":
                clips["t%d" % part[1]] = segs_text[part[1]]
    clips["says"] = L.spoken(r["says"])
    for p in names_needed["you"]:
        for n in you:
            clips["you:%s:%s" % (n, p)] = n + p
    for p in names_needed["them"]:
        for o in rogues:
            if o["name"] != r["name"]:
                clips["them:%s:%s" % (o["name"], p)] = o["name"] + p
    for n in range(NUM_MAX + 1):
        clips["num:%d" % n] = number_words(n).capitalize() + "."
    return clips


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--audition", type=Path, default=None)
    args = ap.parse_args()
    data = json.loads((HERE / "lines.json").read_text())
    templates, rogues, you = data["templates"], data["rogues"], data["you"]
    design_path = HERE / "cast_voices.json"
    designs = json.loads(design_path.read_text()) if design_path.exists() else {}
    fresh = cast(rogues)
    for n, d in fresh.items():
        designs.setdefault(n, d)
    design_path.write_text(json.dumps(designs, indent=2) + "\n")
    low = {n: d["packs"] for n, d in designs.items() if any(pk not in GRADES for pk in d["packs"])}
    if low:
        sys.exit("voices cast with low-grade packs (recast them: delete their entries): %s" % low)

    # the plans: every template's parts, words as shared segment ids
    global segs_text, names_needed
    segs_text, seg_id, plans = [], {}, {}
    for k in sorted(templates):
        out = []
        for part in L.parts(templates[k]):
            if part[0] == "t":
                if part[1] not in seg_id:
                    seg_id[part[1]] = len(segs_text)
                    segs_text.append(part[1])
                out.append(["t", seg_id[part[1]]])
            else:
                out.append(part)
        plans[k] = out
    names_needed = L.names_said(templates)

    from kokoro import KPipeline  # (slow to import: after the cheap checks)
    pipes = {lang: KPipeline(lang_code=lang, repo_id="hexgrad/Kokoro-82M") for lang in ("a", "b")}
    only = {s.strip() for s in args.only.split(",") if s.strip()}
    OUT.mkdir(parents=True, exist_ok=True)
    bank_path = OUT / "voices.json"
    bank = json.loads(bank_path.read_text()) if bank_path.exists() and only else {"rogues": {}}
    for r in rogues:
        if only and r["name"] not in only:
            continue
        v = Voice(pipes, designs[r["name"]])
        if args.audition:
            args.audition.mkdir(parents=True, exist_ok=True)
            pick = [r["says"], templates["p.%s.spot.0" % r["voice"]].format(you="Bun", k=3, w=2),
                    templates["o.cheese_hat.spot.0"].format(you="Fox"), templates["h.3.spot.0"].format(you="Bun", w=5)]
            x = np.concatenate([np.concatenate([v.say(L.spoken(t)), np.zeros(int(SR * 0.4), np.float32)]) for t in pick])
            sf.write(args.audition / ("%s.wav" % slug(r["name"])), x, SR)
            print("AUDITION", r["name"], designs[r["name"]], flush=True)
            continue
        clips = rogue_clips(r, templates, plans, seg_id, you, rogues)
        pieces, index, t = [], {}, 0.0
        gap = np.zeros(int(SR * GAP), np.float32)
        for cid in sorted(clips):
            x = v.say(clips[cid])
            index[cid] = [round(t, 4), round(len(x) / SR, 4)]
            pieces += [x, gap]
            t += (len(x) + len(gap)) / SR
        audio = np.concatenate(pieces)
        name = slug(r["name"]) + ".ogg"
        encode(audio, OUT / name)
        bank["rogues"][r["name"]] = {"file": name, "clips": index}
        print("VOICED %-18s %4d clips %6.1f s %5.2f MB" % (r["name"], len(index), t, (OUT / name).stat().st_size / 1e6), flush=True)
    if args.audition:
        return
    bank["plans"] = plans
    bank["voices"] = {n: designs[n] for n in bank["rogues"]}
    bank_path.write_text(json.dumps(bank, separators=(",", ":")) + "\n")
    print("WROTE", bank_path, len(bank["rogues"]), "rogues")
    write_credits(sorted(OUT.glob("*.ogg")))


def write_credits(files: list[Path]) -> None:
    entry = {
        "asset": "The rogues' voices (every taunt, %d rogues)" % len(files),
        "author": "Synthesized with Kokoro-82M by hexgrad",
        "author_url": "https://huggingface.co/hexgrad",
        "source_url": "https://huggingface.co/hexgrad/Kokoro-82M",
        "license": "Apache 2.0",
        "license_url": "https://www.apache.org/licenses/LICENSE-2.0",
        "changes": "Each rogue's lines spoken by tools/voices/build_voices.py in a voice of its own: two Kokoro "
                   "voice packs blended, pitched for its kind of critter and paced for its personality "
                   "(tools/voices/cast_voices.json), trimmed, levelled and packed into one Ogg Vorbis file per rogue",
        "used_for": "Rogues speaking their taunts out loud",
        "files": [str(f.relative_to(ROOT)) for f in files] + ["assets/voices/voices.json"],
    }
    path = ROOT / "assets" / "credits" / "voices.json"
    path.write_text(json.dumps([entry], indent=2) + "\n")
    print("WROTE", path)


if __name__ == "__main__":
    main()
