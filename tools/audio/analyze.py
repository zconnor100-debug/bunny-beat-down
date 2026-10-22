"""Measure rendered sounds (and compare two renders) without listening.

Runs inside Blender's Python (numpy + aud, like build_audio.py):

    /snap/bin/blender -b --factory-startup --python tools/audio/analyze.py -- \\
        [--png OUT_DIR] [--before DIR] FILE_OR_KEY ...

FILE_OR_KEY is an audio file, or a manifest key (all of its variants in
assets/audio/sfx). With --before DIR (a copy of an older assets/audio/sfx), each
file is also measured in DIR and the deltas are printed. --png writes a
log-frequency spectrogram per file (before|after side by side with --before).

Columns:
  dur     length (s)              peak    sample peak (dBFS)
  loud    max 50 ms K-weighted RMS, the build's loudness number (dB)
  cent    spectral centroid (Hz): lower = darker / deeper
  low%    share of energy below 200 Hz: higher = more body / boom
  punch   crest of the first 60 ms (peak minus RMS, dB) and how fast it gets
          there: attack (ms, 10% -> 90% of the envelope peak)
  t20     time for the envelope to fall 20 dB below its peak (ms): ring / tail
"""
import os
import struct
import sys
import zlib

import numpy as np

import aud  # Blender-only

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import dsp  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
SFX = os.path.join(ROOT, "assets", "audio", "sfx")
SR = dsp.SR


def load(path):
    s = aud.Sound(path).resample(SR, True).rechannel(1)
    return s.data()[:, 0].astype(np.float64)


def envelope(x, win=0.005):
    n = max(1, int(win * SR))
    return np.sqrt(np.convolve(x * x, np.ones(n) / n, mode="same") + 1e-18)


def measure(x):
    pk = float(np.max(np.abs(x)) + 1e-12)
    spec = np.abs(np.fft.rfft(x * np.hanning(len(x)))) ** 2
    freqs = np.fft.rfftfreq(len(x), 1 / SR)
    tot = float(spec.sum()) + 1e-18
    env = envelope(x)
    ip = int(np.argmax(env))
    ep = env[ip]
    above10 = np.nonzero(env[: ip + 1] >= 0.1 * ep)[0]
    above90 = np.nonzero(env[: ip + 1] >= 0.9 * ep)[0]
    attack = (above90[0] - above10[0]) / SR * 1000 if len(above10) and len(above90) else 0.0
    after = np.nonzero(env[ip:] < ep * 0.1)[0]
    t20 = after[0] / SR * 1000 if len(after) else (len(env) - ip) / SR * 1000
    head = x[: int(0.06 * SR)]
    crest = 20 * np.log10(np.max(np.abs(head)) / (np.sqrt(np.mean(head ** 2)) + 1e-12) + 1e-12)
    return {
        "dur": len(x) / SR,
        "peak": 20 * np.log10(pk),
        "loud": dsp.loudness_db(x),
        "cent": float((freqs * spec).sum() / tot),
        "low%": 100.0 * float(spec[freqs < 200].sum()) / tot,
        "punch": crest,
        "attack": attack,
        "t20": t20,
    }


COLS = [("dur", "{:5.2f}"), ("peak", "{:6.1f}"), ("loud", "{:6.1f}"), ("cent", "{:6.0f}"),
        ("low%", "{:5.1f}"), ("punch", "{:5.1f}"), ("attack", "{:5.1f}"), ("t20", "{:6.0f}")]


def row(m):
    return "  ".join(f.format(m[k]) for k, f in COLS)


# ---- spectrogram PNG (no PIL in Blender's Python) -----------------------
def _png(path, rgb):
    h, w, _ = rgb.shape
    raw = b"".join(b"\x00" + rgb[y].astype(np.uint8).tobytes() for y in range(h))

    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def spectrogram(x, w=480, h=240, dur=None):
    """Log-frequency (30 Hz..20 kHz) spectrogram, 80 dB range, as an RGB array."""
    dur = dur or len(x) / SR
    n = 2048
    hops = np.linspace(0, max(0, int(dur * SR) - 1), w).astype(int)
    xp = np.pad(x, (n, n + max(0, int(dur * SR) - len(x))))  # the shorter of a before|after pair
    win = np.hanning(n)
    freqs = np.fft.rfftfreq(n, 1 / SR)
    bands = np.geomspace(30, 20000, h + 1)
    img = np.zeros((h, w))
    for i, c in enumerate(hops):
        seg = xp[c + n // 2: c + n // 2 + n] * win
        p = np.abs(np.fft.rfft(seg)) ** 2
        idx = np.clip(np.searchsorted(freqs, bands), 0, len(p) - 1)
        img[:, i] = [p[a:max(b, a + 1)].mean() for a, b in zip(idx[:-1], idx[1:])]
    db = 10 * np.log10(img + 1e-14)
    db = np.clip((db - (db.max() - 80)) / 80, 0, 1)[::-1]
    # dark blue -> magenta -> orange -> pale yellow
    stops = np.array([[0, 0, 10], [80, 20, 120], [200, 50, 90], [250, 150, 40], [255, 250, 200]], float)
    pos = db * (len(stops) - 1)
    lo = np.floor(pos).astype(int).clip(0, len(stops) - 2)
    t = (pos - lo)[..., None]
    return stops[lo] * (1 - t) + stops[lo + 1] * t


def resolve(arg):
    if os.path.exists(arg):
        return [arg]
    out = sorted(os.path.join(SFX, f) for f in os.listdir(SFX)
                 if f == f"{arg}.ogg" or (f.startswith(f"{arg}_") and f[len(arg) + 1:-4].isdigit()))
    if not out:
        print(f"?? nothing for {arg}")
    return out


def main(argv):
    png = before = None
    if "--png" in argv:
        i = argv.index("--png")
        png = argv[i + 1]
        del argv[i:i + 2]
        os.makedirs(png, exist_ok=True)
    if "--before" in argv:
        i = argv.index("--before")
        before = argv[i + 1]
        del argv[i:i + 2]
    print(f"{'file':34s}  " + "  ".join(f"{k:>{len(f.format(0))}s}" for k, f in COLS))
    for arg in argv:
        for path in resolve(arg):
            name = os.path.basename(path)
            x = load(path)
            m = measure(x)
            print(f"{name:34s}  {row(m)}")
            old = os.path.join(before, name) if before else None
            if old and os.path.exists(old):
                y = load(old)
                mo = measure(y)
                print(f"{'  (before)':34s}  {row(mo)}")
                print(f"{'  (delta)':34s}  " + "  ".join(f.replace(":", ":+").format(m[k] - mo[k]) for k, f in COLS))
            elif before:
                print(f"{'  (before)':34s}  -- new file --")
            if png:
                if old and os.path.exists(old):
                    d = max(len(x), len(y)) / SR
                    img = np.concatenate([spectrogram(y, dur=d), np.full((240, 6, 3), 255.0), spectrogram(x, dur=d)], axis=1)
                else:
                    img = spectrogram(x)
                _png(os.path.join(png, name.rsplit(".", 1)[0] + ".png"), img)


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    main(args)
