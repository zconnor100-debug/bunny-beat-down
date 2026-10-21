"""Tiny numpy DSP toolkit used by the Bunny Beat Down sound recipes.

Everything works on mono float64 numpy arrays at SR = 44100 Hz. No scipy:
static filters are done in the frequency domain (zero-phase FFT filtering),
time-varying filters with an STFT overlap-add, and the few genuinely
recursive things (Karplus-Strong plucks) are vectorised per period.

All randomness goes through an explicit numpy Generator so every build is
bit-for-bit reproducible.
"""
import numpy as np

SR = 44100


# --------------------------------------------------------------------------
# basics
# --------------------------------------------------------------------------
def n_of(dur):
    return max(1, int(round(dur * SR)))


def times(n):
    return np.arange(n) / SR


def zeros(dur):
    return np.zeros(n_of(dur))


def db(x):
    return 10.0 ** (x / 20.0)


def pad_to(x, n):
    if len(x) >= n:
        return x[:n]
    return np.concatenate([x, np.zeros(n - len(x))])


def mix(length, *layers):
    """Sum layers into one buffer, at least `length` seconds long (it grows to
    fit the longest layer, so ringing tails are never chopped off; build_audio
    trims trailing silence afterwards).

    Each layer is (signal, offset_seconds, gain_db).
    """
    end = max([n_of(length)] + [int(round(off * SR)) + len(sig) for sig, off, _ in layers])
    out = np.zeros(end)
    for sig, off, gain in layers:
        i0 = int(round(off * SR))
        if i0 >= len(out):
            continue
        seg = sig[: len(out) - i0] * db(gain)
        # short fade-out on every layer so a block that is cut while still
        # ringing (or truncated by the buffer) never ends in a click
        f = min(n_of(0.01), len(seg) // 4)
        if f > 1:
            seg = seg.copy()
            seg[-f:] *= 0.5 + 0.5 * np.cos(np.linspace(0, np.pi, f))
        out[i0 : i0 + len(seg)] += seg
    return out


def fade(x, fin=0.002, fout=0.01):
    """Raised-cosine fade in/out (removes clicks at file boundaries)."""
    x = x.copy()
    a, b = min(len(x), n_of(fin)), min(len(x), n_of(fout))
    if a > 1:
        x[:a] *= 0.5 - 0.5 * np.cos(np.linspace(0, np.pi, a))
    if b > 1:
        x[-b:] *= 0.5 + 0.5 * np.cos(np.linspace(0, np.pi, b))
    return x


def trim(x, thresh_db=-60.0, keep_head=True, tail=0.02):
    """Trim trailing (and optionally leading) audio below thresh relative to peak."""
    pk = np.max(np.abs(x)) + 1e-12
    idx = np.nonzero(np.abs(x) > pk * db(thresh_db))[0]
    if not len(idx):
        return x
    start = 0 if keep_head else max(0, idx[0] - n_of(0.002))
    end = min(len(x), idx[-1] + n_of(tail))
    return x[start:end]


def cut(x, start, dur=None):
    """Slice by seconds."""
    a = n_of(start) if start > 0 else 0
    b = len(x) if dur is None else a + n_of(dur)
    return x[a:b]


# --------------------------------------------------------------------------
# envelopes
# --------------------------------------------------------------------------
def env_exp(n, attack=0.002, tau=0.1):
    """Linear attack then exponential decay with time constant tau (s)."""
    t = times(n)
    a = max(attack, 1e-5)
    e = np.where(t < a, t / a, np.exp(-(t - a) / tau))
    return e


def env_pts(n, pts):
    """Piecewise-linear envelope through [(time_s, value), ...]."""
    ts, vs = zip(*pts)
    return np.interp(times(n), ts, vs)


def glide(n, f0, f1, tau):
    """Exponential frequency glide f0 -> f1 with time constant tau."""
    t = times(n)
    return f1 + (f0 - f1) * np.exp(-t / tau)


# --------------------------------------------------------------------------
# oscillators / noise
# --------------------------------------------------------------------------
def phase_of(freq, n=None, phase0=0.0):
    f = np.full(n, float(freq)) if np.isscalar(freq) else np.asarray(freq, float)
    return phase0 + 2 * np.pi * np.cumsum(f) / SR


def sine(freq, n, phase0=0.0):
    return np.sin(phase_of(freq, n, phase0))


def additive(freq, n, partials, phase0=0.0):
    """Sum of harmonics: partials = [(ratio, amp), ...]; skips anything near Nyquist."""
    ph = phase_of(freq, n, phase0)
    fmax = np.max(freq) if not np.isscalar(freq) else freq
    out = np.zeros(len(ph))
    for r, a in partials:
        if r * fmax < SR * 0.45:
            out += a * np.sin(ph * r)
    return out


def saw_bl(freq, n, max_h=40):
    """Band-limited sawtooth via additive synthesis (time-varying freq ok)."""
    f = np.full(n, float(freq)) if np.isscalar(freq) else np.asarray(freq, float)
    ph = phase_of(f)
    out = np.zeros(n)
    for k in range(1, max_h + 1):
        mask = (k * f) < SR * 0.45
        if not mask.any():
            break
        out += mask * np.sin(ph * k) / k
    return out * (2 / np.pi)


def white(n, rng):
    return rng.standard_normal(n)


def colored(n, rng, slope_db_oct=-3.0):
    """Noise with a spectral slope (-3 = pink, -6 = brown)."""
    spec = np.fft.rfft(rng.standard_normal(n))
    f = np.fft.rfftfreq(n, 1 / SR)
    f[0] = f[1]
    spec *= (f / 1000.0) ** (slope_db_oct / 6.0206)
    # 4th-order high-pass at 20 Hz: without it pink/brown noise is dominated by
    # inaudible sub-sonic drift, which wastes headroom and fools the normaliser
    spec *= 1 / np.sqrt(1 + (20.0 / f) ** 8)
    x = np.fft.irfft(spec, n)
    return x / (np.std(x) + 1e-12)


def smooth_rand(n, rng, rate_hz, period=None):
    """Smooth random control signal in [-1, 1].

    With `period` (seconds) the signal is built from sinusoids that complete an
    integer number of cycles in `period`, so it loops seamlessly.
    """
    t = times(n)
    out = np.zeros(n)
    if period:
        kmax = max(1, int(rate_hz * period))
        for k in range(1, kmax + 1):
            out += rng.normal() / k ** 0.7 * np.sin(2 * np.pi * k / period * t + rng.uniform(0, 2 * np.pi))
    else:
        for _ in range(6):
            f = rate_hz * rng.uniform(0.3, 1.0)
            out += rng.normal() * np.sin(2 * np.pi * f * t + rng.uniform(0, 2 * np.pi))
    return out / (np.max(np.abs(out)) + 1e-12)


# --------------------------------------------------------------------------
# filters (frequency domain)
# --------------------------------------------------------------------------
def _fft_apply(x, gain_fn, pad=0.05):
    n = len(x)
    m = 1 << int(np.ceil(np.log2(n + n_of(pad))))
    spec = np.fft.rfft(x, m)
    f = np.fft.rfftfreq(m, 1 / SR)
    spec *= gain_fn(f)
    return np.fft.irfft(spec, m)[:n]


def lowpass(x, fc, order=2):
    return _fft_apply(x, lambda f: 1 / np.sqrt(1 + (f / fc) ** (2 * order)))


def highpass(x, fc, order=2):
    return _fft_apply(x, lambda f: 1 / np.sqrt(1 + (fc / np.maximum(f, 1e-3)) ** (2 * order)))


def bandpass(x, fc, q=1.0):
    def g(f):
        f = np.maximum(f, 1e-3)
        return 1 / np.sqrt(1 + q * q * (f / fc - fc / f) ** 2)
    return _fft_apply(x, g)


def peak_eq(x, fc, gain_db, q=1.0):
    def g(f):
        f = np.maximum(f, 1e-3)
        bump = 1 / np.sqrt(1 + q * q * (f / fc - fc / f) ** 2)
        return 1 + (db(gain_db) - 1) * bump
    return _fft_apply(x, g)


def stft_filter(x, gain_fn, win=2048, hop=512):
    """Time-varying zero-phase filter: gain_fn(t_frames[:,None], f[None,:]) -> gains."""
    n = len(x)
    w = np.hanning(win)
    xp = np.concatenate([np.zeros(win), x, np.zeros(win)])
    starts = np.arange(0, len(xp) - win, hop)
    frames = np.stack([xp[s : s + win] * w for s in starts])
    spec = np.fft.rfft(frames, axis=1)
    tf = (starts + win / 2 - win) / SR
    f = np.fft.rfftfreq(win, 1 / SR)
    spec *= gain_fn(tf[:, None], f[None, :])
    frames = np.fft.irfft(spec, win, axis=1) * w
    out = np.zeros(len(xp))
    norm = np.zeros(len(xp))
    for i, s in enumerate(starts):
        out[s : s + win] += frames[i]
        norm[s : s + win] += w * w
    out /= np.maximum(norm, 1e-6)
    return out[win : win + n]


def bp_gain(f, fc, q):
    """Band-pass magnitude usable inside stft_filter gain functions."""
    f = np.maximum(f, 1e-3)
    return 1 / np.sqrt(1 + q * q * (f / fc - fc / f) ** 2)


# --------------------------------------------------------------------------
# time / pitch
# --------------------------------------------------------------------------
def varispeed(x, ratio):
    """Tape-style resample: ratio > 1 = faster & higher. ratio may be an array
    (per output sample) for pitch bends."""
    if np.isscalar(ratio):
        n_out = int(len(x) / ratio)
        pos = np.arange(n_out) * ratio
    else:
        pos = np.cumsum(ratio)
        pos = pos[pos < len(x) - 1]
    return np.interp(pos, np.arange(len(x)), x)


def fftconvolve(a, b):
    n = len(a) + len(b) - 1
    m = 1 << int(np.ceil(np.log2(n)))
    return np.fft.irfft(np.fft.rfft(a, m) * np.fft.rfft(b, m), m)[:n]


def reverb(x, rng, decay=0.6, mix_db=-12.0, predelay=0.012, bright=5000.0, tail=None):
    """Cheap natural reverb: convolve with exponentially decaying filtered noise."""
    L = n_of(decay * 1.2)
    ir = rng.standard_normal(L) * np.exp(-times(L) * 6.9 / decay)
    ir = lowpass(ir, bright, 1)
    ir = np.concatenate([np.zeros(n_of(predelay)), ir])
    ir /= np.sqrt(np.sum(ir ** 2)) + 1e-12
    wet = fftconvolve(x, ir)
    out_len = len(x) + (n_of(tail) if tail is not None else len(ir))
    dry = pad_to(x, out_len)
    wet = pad_to(wet, out_len)
    return dry + wet * db(mix_db)


def saturate(x, drive=2.0):
    """Soft tanh saturation, gain-compensated."""
    return np.tanh(x * drive) / np.tanh(drive)


# --------------------------------------------------------------------------
# instruments
# --------------------------------------------------------------------------
def pluck(freq, dur, rng, decay=0.996, bright=0.5):
    """Karplus-Strong plucked string, vectorised per period."""
    n = n_of(dur)
    P = max(2, int(round(SR / freq)))
    buf = rng.uniform(-1, 1, P)
    buf = lowpass(buf, 1500 + 8000 * bright, 1) if P > 64 else buf
    out = np.zeros(n + P)
    out[:P] = buf
    i = P
    while i < n + P:
        j = min(i + P, n + P)
        prev = out[i - P : j - P]
        prev2 = out[i - P - 1 : j - P - 1] if i - P - 1 >= 0 else np.concatenate([[0.0], out[i - P : j - P - 1]])
        out[i:j] = decay * 0.5 * (prev + prev2)
        i = j
    y = out[:n]
    # natural release over the last 40 % so short plucks never stop dead
    r = int(n * 0.4)
    if r > 1:
        y[-r:] *= 0.5 + 0.5 * np.cos(np.linspace(0, np.pi, r))
    return y / (np.max(np.abs(y)) + 1e-12)


def bell(freq, dur, partials=((1, 1.0, 1.0), (2.0, 0.5, 0.6), (3.0, 0.25, 0.45), (4.2, 0.12, 0.3)),
         tau=0.4, attack=0.002):
    """Additive bell/glock: partials = (ratio, amp, decay_scale).

    The buffer is extended until the slowest partial has rung out (~-48 dB),
    so `dur` is a minimum, never a hard cut."""
    n = n_of(max(dur, tau * max(p[2] for p in partials) * 5.5))
    t = times(n)
    out = np.zeros(n)
    for r, a, ds in partials:
        if freq * r < SR * 0.45:
            out += a * np.sin(2 * np.pi * freq * r * t) * np.exp(-t / (tau * ds))
    atk = np.clip(t / attack, 0, 1)
    return out * atk


def midi_hz(m):
    return 440.0 * 2 ** ((m - 69) / 12.0)


# --------------------------------------------------------------------------
# loops / loudness
# --------------------------------------------------------------------------
def make_loop(x, length, xfade):
    """x must be >= length + xfade seconds. Equal-power crossfade the overhang
    back onto the start so sample[length-1] -> sample[0] is seamless."""
    L, X = n_of(length), n_of(xfade)
    assert len(x) >= L + X, "make_loop needs length + xfade of material"
    out = x[:L].copy()
    th = np.linspace(0, np.pi / 2, X)
    out[:X] = x[:X] * np.sin(th) + x[L : L + X] * np.cos(th)
    return out


def fold_circular(x, length):
    """Wrap everything past `length` back onto the start (for event-based loops)."""
    L = n_of(length)
    out = np.zeros(L)
    for i in range(0, len(x), L):
        seg = x[i : i + L]
        out[: len(seg)] += seg
    return out


def short_term_rms_db(x, win=0.05):
    w = n_of(win)
    if len(x) <= w:
        return 20 * np.log10(np.sqrt(np.mean(x ** 2)) + 1e-12)
    c = np.cumsum(np.concatenate([[0], x ** 2]))
    ms = (c[w:] - c[:-w]) / w
    return 10 * np.log10(np.max(ms) + 1e-12)


def k_weight(x):
    """Approximate ITU-R BS.1770 K-weighting (high-pass ~40 Hz + ~+4 dB
    shelf above ~1.5 kHz), so bass-heavy thumps are not judged louder than
    they sound."""
    def g(f):
        f2 = f * f
        shelf = 1 + (db(4.0) - 1) * f2 / (f2 + 1500.0 ** 2)
        hp = 1 / np.sqrt(1 + (40.0 / np.maximum(f, 1e-3)) ** 4)
        return shelf * hp
    return _fft_apply(x, g)


def loudness_db(x, win=0.05):
    """Max short-term (50 ms) K-weighted RMS in dBFS -- our 'how loud is it' number."""
    return short_term_rms_db(k_weight(x), win)


def normalize(x, target_db, ceiling_db=-1.0, limit=True):
    """Scale so the loudest 50 ms window sits at target_db (K-weighted RMS);
    peaks above the ceiling are soft-limited (tanh knee) rather than clipping."""
    g = db(target_db - loudness_db(x))
    y = x * g
    c = db(ceiling_db)
    pk = np.max(np.abs(y))
    if pk > c:
        if limit and pk < c * 2.0:
            knee = 0.7 * c
            a = np.abs(y)
            over = a > knee
            y = np.where(over, np.sign(y) * (knee + (c - knee) * np.tanh((a - knee) / (c - knee))), y)
        else:
            y *= c / pk
    return y
