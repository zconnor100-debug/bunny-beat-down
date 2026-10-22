"""Build every Bunny Beat Down sound effect + the audio manifest + audio credits.

Runs inside Blender's bundled Python, because Blender ships numpy and the
`aud` (Audaspace) module, whose FFmpeg backend decodes Kenney's .ogg files and
encodes our output to Ogg Vorbis (there is no system ffmpeg/sox/oggenc):

    python3 -I tools/audio/fetch_sources.py          # once: downloads into tools/_cache/audio/
    /snap/bin/blender -b --factory-startup --python-exit-code 1 \
        --python tools/audio/build_audio.py           # full rebuild
    ... --python tools/audio/build_audio.py -- --only hop,headshot   # subset (manifest untouched)
    ... -- --only hop --out /tmp/try    # subset into /tmp/try/sfx/ (assets untouched)

Outputs (all paths relative to the repo root):
    assets/audio/sfx/<key>[_<n>].ogg     mono 44.1 kHz Ogg Vorbis
    assets/audio/music/*.mp3             Kevin MacLeod tracks, copied unchanged
    assets/audio/manifest.json           key -> [files], plus "music"
    assets/credits/audio.json            one entry per source pack / track / synth set
"""
import json
import os
import shutil
import struct
import sys
import zlib

import numpy as np

import aud  # Blender-only

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import dsp  # noqa: E402
import recipes  # noqa: E402
import sources  # noqa: E402

# Work-in-progress recipe modules (recipes_wip_<group>.py) re-register keys to
# override recipes.py while a group of sounds is being reworked (see README
# "Iterating on sounds"); merge them into recipes.py when done. A broken one is
# skipped with a warning so other groups can keep building.
import glob  # noqa: E402
import importlib  # noqa: E402
import traceback  # noqa: E402
for _p in sorted(glob.glob(os.path.join(HERE, "recipes_wip_*.py"))):
    try:
        importlib.import_module(os.path.splitext(os.path.basename(_p))[0])
    except Exception:
        print(f"WARNING: skipping {os.path.basename(_p)}:\n{traceback.format_exc()}")

ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
CACHE = os.path.join(ROOT, "tools", "_cache", "audio")
OUT = os.path.join(ROOT, "assets", "audio")
MUSIC = os.path.join(OUT, "music")
CREDITS = os.path.join(ROOT, "assets", "credits", "audio.json")

SR = dsp.SR
MAX_ONESHOT_S = 3.0
MAX_LOOP_S = 10.0
VORBIS_BITRATE = 128000


# --------------------------------------------------------------------------
# audio I/O through Audaspace
# --------------------------------------------------------------------------
def load_mono(path, hq=False):
    """Decode any audio file to mono float64 at SR. hq=True uses Audaspace's
    high-quality resampler (used for the 96 kHz OpenGameArt recordings)."""
    s = aud.Sound(path).resample(SR, hq).rechannel(1)
    return s.data()[:, 0].astype(np.float64)


def write_ogg(path, x):
    buf = np.ascontiguousarray(np.clip(x, -1, 1).astype(np.float32).reshape(-1, 1))
    tmp = path + ".tmp.ogg"
    aud.Sound.buffer(buf, SR).write(tmp, SR, aud.CHANNELS_MONO, aud.FORMAT_FLOAT32,
                                    aud.CONTAINER_OGG, aud.CODEC_VORBIS, VORBIS_BITRATE)
    stabilise_ogg(tmp, zlib.crc32(os.path.basename(path).encode()))
    os.replace(tmp, path)


# FFmpeg gives every Ogg stream a random serial number, so identical audio
# would produce different bytes on each build (noisy git diffs). Rewrite the
# serial to a value derived from the file name and fix each page's CRC.
def _ogg_crc_table():
    table = []
    for i in range(256):
        r = i << 24
        for _ in range(8):
            r = ((r << 1) ^ 0x04C11DB7) if r & 0x80000000 else (r << 1)
            r &= 0xFFFFFFFF
        table.append(r)
    return table


_OGG_CRC = _ogg_crc_table()


def _ogg_crc(data):
    crc = 0
    for b in data:
        crc = ((crc << 8) & 0xFFFFFFFF) ^ _OGG_CRC[((crc >> 24) & 0xFF) ^ b]
    return crc


def stabilise_ogg(path, serial):
    with open(path, "rb") as f:
        data = bytearray(f.read())
    i = 0
    while i < len(data):
        if data[i : i + 4] != b"OggS":
            raise SystemExit(f"{path}: not an Ogg page at byte {i}")
        nseg = data[i + 26]
        page_len = 27 + nseg + sum(data[i + 27 : i + 27 + nseg])
        data[i + 14 : i + 18] = struct.pack("<I", serial)
        data[i + 22 : i + 26] = b"\0\0\0\0"
        data[i + 22 : i + 26] = struct.pack("<I", _ogg_crc(bytes(data[i : i + page_len])))
        i += page_len
    with open(path, "wb") as f:
        f.write(data)


# --------------------------------------------------------------------------
# build context handed to recipes
# --------------------------------------------------------------------------
class Ctx:
    def __init__(self):
        self.index = {}  # pack -> {stem: path}
        for pack in sources.KENNEY_PACKS:
            d = os.path.join(CACHE, "kenney", pack)
            if not os.path.isdir(d):
                raise SystemExit(f"missing {d} -- run tools/audio/fetch_sources.py first")
            stems = {}
            for dirpath, _, files in os.walk(d):
                for f in files:
                    if f.lower().endswith(".ogg") and not f.startswith("Preview"):
                        stems[os.path.splitext(f)[0]] = os.path.join(dirpath, f)
            self.index[pack] = stems
        self._raw = {}
        self.rng = None
        self.used = set()
        self.used_oga = set()

    def begin(self, key, v):
        self.rng = np.random.default_rng(zlib.crc32(f"{key}:{v}".encode()))
        self.used = set()
        self.used_oga = set()

    def o(self, oid, rel):
        """Whole OpenGameArt recording -> peak-normalised mono array at SR.
        `rel` is the path inside tools/_cache/audio/oga/<oid>/ (or '' for a
        single-file source)."""
        meta = sources.OGA[oid]
        if meta["archive"]:
            path = os.path.join(CACHE, "oga", oid, rel)
        else:
            path = os.path.join(CACHE, "oga", oid + os.path.splitext(meta["url"])[1])
            rel = os.path.basename(meta["url"])
        if not os.path.exists(path):
            raise SystemExit(f"missing {path} -- run tools/audio/fetch_sources.py oga")
        if path not in self._raw:
            self._raw[path] = load_mono(path, hq=True)
        self.used_oga.add((oid, rel))
        x = self._raw[path]
        return x / (np.max(np.abs(x)) + 1e-12)

    def k(self, pack, stem, speed=1.0, start=0.0, dur=None):
        """Kenney clip -> peak-normalised mono array (optionally sped up / sliced)."""
        path = self.index[pack][stem]
        if path not in self._raw:
            self._raw[path] = load_mono(path)
        rel = os.path.relpath(path, os.path.join(CACHE, "kenney", pack))
        self.used.add((pack, rel))
        x = self._raw[path]
        if start or dur:
            x = dsp.cut(x, start, dur)
        if speed != 1.0:
            x = dsp.varispeed(x, speed)
        return x / (np.max(np.abs(x)) + 1e-12)


def finish(x, spec):
    """Trim/fade/normalise one rendered variant."""
    x = np.nan_to_num(np.asarray(x, float))
    if spec["loop"]:
        assert len(x) / SR <= MAX_LOOP_S + 1e-6, spec["key"]
        return dsp.normalize(x, spec["loud"], ceiling_db=-1.0)
    x = dsp.trim(x, -50.0, keep_head=True, tail=0.03)
    x = x[: dsp.n_of(MAX_ONESHOT_S)]
    x = dsp.highpass(x, 35, 2)  # strip DC / sub-sonic rumble (inaudible, eats headroom)
    x = dsp.fade(x, 0.0015, 0.03)
    return dsp.normalize(x, spec["loud"], ceiling_db=-1.0)


# --------------------------------------------------------------------------
# main
# --------------------------------------------------------------------------
def build(only=None, out=OUT):
    os.makedirs(os.path.join(out, "sfx"), exist_ok=True)
    os.makedirs(MUSIC, exist_ok=True)
    c = Ctx()
    manifest = {}
    provenance = {}  # out file -> {"src":..., "kenney": [(pack, rel), ...]}
    report = []
    for spec in recipes.RECIPES:
        key = spec["key"]
        files = []
        for v in range(spec["variants"]):
            name = f"{key}_{v + 1}.ogg" if spec["variants"] > 1 else f"{key}.ogg"
            rel = f"sfx/{name}"
            files.append(rel)
            if only and key not in only:
                continue
            c.begin(key, v)
            x = finish(spec["fn"](c, v), spec)
            write_ogg(os.path.join(out, rel), x)
            provenance[rel] = {"src": spec["src"], "kenney": sorted(c.used), "key": key,
                               "oga": sorted(c.used_oga)}
            pk = 20 * np.log10(np.max(np.abs(x)) + 1e-12)
            report.append((rel, len(x) / SR, pk, dsp.loudness_db(x),
                           os.path.getsize(os.path.join(out, rel))))
        manifest[key] = files

    for rel, dur, pk, st, size in report:
        print(f"  {rel:38s} {dur:5.2f}s  peak {pk:6.1f} dB  loud {st:6.1f} dB  {size/1024:6.1f} KB")

    if only:
        print("partial build: manifest/credits not rewritten")
        return

    # ---- music: copy the official MP3s unchanged ----
    music = {"menu": None, "match": [], "victory": None}
    for t in sources.MUSIC:
        src = os.path.join(CACHE, "incompetech", t["cache_name"])
        if not os.path.exists(src):
            raise SystemExit(f"missing {src} -- run tools/audio/fetch_sources.py music")
        shutil.copyfile(src, os.path.join(OUT, t["file"]))
        if t["slot"] == "match":
            music["match"].append(t["file"])
        else:
            music[t["slot"]] = t["file"]
    manifest["music"] = music

    with open(os.path.join(OUT, "manifest.json"), "w") as f:
        json.dump(manifest, f, indent=2)
        f.write("\n")

    write_credits(provenance)
    total = sum(os.path.getsize(os.path.join(dp, fn)) for dp, _, fns in os.walk(OUT) for fn in fns)
    print(f"assets/audio total: {total / 1e6:.2f} MB")


def write_credits(provenance):
    lic0, lic0_url = sources.CC0
    entries = []
    for pack, meta in sources.KENNEY_PACKS.items():
        files = sorted(rel for rel, p in provenance.items() if any(u[0] == pack for u in p["kenney"]))
        if not files:
            continue
        keys = sorted({provenance[r]["key"] for r in files})
        src_files = sorted({u[1] for r in files for u in provenance[r]["kenney"] if u[0] == pack})
        entries.append({
            "asset": f"{meta['title']} (Kenney audio pack)",
            "author": "Kenney",
            "author_url": "https://kenney.nl",
            "source_url": f"https://kenney.nl/assets/{pack}",
            "license": lic0,
            "license_url": lic0_url,
            "changes": ("Selected clips trimmed, resampled/pitch-shifted, filtered, level-normalised "
                        "and in most cases layered with other Kenney clips and/or original synthesized "
                        "layers (see tools/audio/recipes.py); downmixed to mono and re-encoded as "
                        "44.1 kHz Ogg Vorbis."),
            "used_for": "Sound effects: " + ", ".join(keys),
            "files": [f"assets/audio/{r}" for r in files],
            "source_files": src_files,
        })

    for oid, meta in sources.OGA.items():
        files = sorted(rel for rel, p in provenance.items() if any(u[0] == oid for u in p["oga"]))
        if not files:
            continue
        keys = sorted({provenance[r]["key"] for r in files})
        src_files = sorted({u[1] for r in files for u in provenance[r]["oga"] if u[0] == oid})
        lic, lic_url = meta["license"]
        entries.append({
            "asset": f"{meta['title']} (OpenGameArt)",
            "author": meta["author"],
            "author_url": meta["author_url"],
            "source_url": meta["page"],
            "license": lic,
            "license_url": lic_url,
            "changes": ("Single shots, hits and steps cut from the recordings, downmixed to mono, "
                        "resampled to 44.1 kHz, tails shortened or extended, pitch-shifted, EQ'd, "
                        "saturated, level-normalised and layered with original synthesized layers "
                        "and Kenney CC0 layers (see tools/audio/recipes.py); re-encoded as Ogg Vorbis."),
            "used_for": "Sound effects: " + ", ".join(keys),
            "files": [f"assets/audio/{r}" for r in files],
            "source_files": src_files,
        })

    synth_files = sorted(r for r, p in provenance.items() if p["src"] in ("synth", "mixed"))
    synth_keys = sorted({provenance[r]["key"] for r in synth_files})
    entries.append({
        "asset": "Synthesized sound effects",
        "author": "Bunny Beat Down project",
        "author_url": "",
        "source_url": "tools/audio/recipes.py",
        "license": "MIT (project)",
        "license_url": "https://opensource.org/licenses/MIT",
        "changes": ("Original sounds generated from code (oscillators, filtered noise, Karplus-Strong "
                    "plucks, formant voices, bells, modal harp / flute / clock / gun-part models, a "
                    "synthesized rock band, gunshot transient/boom/echo layers); files marked 'mixed' in "
                    "recipes.py also contain the Kenney / OpenGameArt layers credited above."),
        "used_for": "Sound effects (fully or partly synthesized): " + ", ".join(synth_keys),
        "files": [f"assets/audio/{r}" for r in synth_files],
    })

    lic, lic_url = sources.CC_BY_4
    for t in sources.MUSIC:
        attribution = (f"\"{t['title']}\" Kevin MacLeod (incompetech.com), "
                       f"Licensed under Creative Commons: By Attribution 4.0 License "
                       f"http://creativecommons.org/licenses/by/4.0/")
        entries.append({
            "asset": f"\"{t['title']}\"",
            "author": "Kevin MacLeod",
            "author_url": "https://incompetech.com",
            "source_url": t["page"],
            "license": lic,
            "license_url": lic_url,
            "changes": "None -- official MP3 from incompetech.com; audio unmodified (file renamed).",
            "used_for": f"Music: {t['slot']} ({t['why']})",
            "files": [f"assets/audio/{t['file']}"],
            "attribution": attribution,
            "isrc": t["isrc"],
        })

    os.makedirs(os.path.dirname(CREDITS), exist_ok=True)
    with open(CREDITS, "w") as f:
        json.dump(entries, f, indent=2, ensure_ascii=False)
        f.write("\n")


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    only = None
    if "--only" in argv:
        only = set(argv[argv.index("--only") + 1].split(","))
    out = OUT
    if "--out" in argv:   # try a subset somewhere else: the game's assets stay as they are
        if not only:
            raise SystemExit("--out needs --only (a full build writes the manifest and credits)")
        out = os.path.abspath(argv[argv.index("--out") + 1])
    build(only, out)
