"""Reusable synthesized sound building blocks (all original, MIT project code).

Every function returns a mono float64 numpy array at dsp.SR. Gains are
roughly unit-peak so recipes can layer them with dB offsets.
"""
import numpy as np

from dsp import (SR, additive, bandpass, bp_gain, colored, env_exp, env_pts,
                 glide, highpass, lowpass, n_of, phase_of, sine, smooth_rand,
                 stft_filter, times, white, zeros)


def unit(x):
    return x / (np.max(np.abs(x)) + 1e-12)


# --------------------------------------------------------------------------
# percussive
# --------------------------------------------------------------------------
def thump(f0, f1, tau_f, tau_a, dur, partial2=0.0):
    """Kick-drum style sine thump with a falling pitch."""
    n = n_of(dur)
    f = glide(n, f0, f1, tau_f)
    x = additive(f, n, [(1, 1.0), (2, partial2)]) if partial2 else sine(f, n)
    return x * env_exp(n, 0.0015, tau_a)


def burst(rng, dur, fc, q, tau, attack=0.0005):
    """Band-passed decaying noise burst."""
    n = n_of(dur)
    x = bandpass(white(n, rng), fc, q)
    return unit(x) * env_exp(n, attack, tau)


def lp_burst(rng, dur, fc, tau, attack=0.003, order=2):
    """Low-passed noise 'whump' (air, canopy, boom bodies)."""
    n = n_of(dur)
    x = lowpass(colored(n, rng, -3), fc, order)
    return unit(x) * env_exp(n, attack, tau)


def crack(rng, tau=0.006, fc=3500.0):
    """Very short high-passed click/crack transient."""
    n = n_of(max(0.03, tau * 8))
    x = highpass(white(n, rng), fc, 2)
    return unit(x) * env_exp(n, 0.0002, tau)


def grains(rng, dur, count, fmin, fmax, glen=(0.002, 0.008), t_tau=0.08, start=0.0):
    """Scatter of tiny band-passed noise grains: dirt spray, splinters, crackle."""
    out = zeros(dur)
    for _ in range(count):
        t0 = start + rng.exponential(t_tau)
        L = n_of(rng.uniform(*glen))
        i0 = n_of(t0)
        if i0 + L >= len(out):
            continue
        g = bandpass(white(L + 64, rng), rng.uniform(fmin, fmax), 2.0)[:L]
        g = unit(g) * env_exp(L, 0.0003, L / SR / 3)
        out[i0 : i0 + L] += g * rng.uniform(0.35, 1.0) * np.exp(-(t0 - start) / (t_tau * 2.5))
    return out


def droplets(rng, dur, count, t_tau=0.15, start=0.02, fmin=700, fmax=2200):
    """Wet 'plips': short upward sine sweeps, like liquid droplets."""
    out = zeros(dur)
    for _ in range(count):
        t0 = start + rng.exponential(t_tau)
        L = n_of(rng.uniform(0.008, 0.03))
        i0 = n_of(t0)
        if i0 + L >= len(out):
            continue
        f0 = rng.uniform(fmin, fmax)
        f = f0 * (1 + 1.3 * times(L) / (L / SR))
        d = sine(f, L) * env_exp(L, 0.001, L / SR / 3)
        out[i0 : i0 + L] += d * rng.uniform(0.3, 1.0) * np.exp(-(t0 - start) / (t_tau * 2))
    return out


def squelch(rng, dur, f_pts, q=3.0, amp_pts=None):
    """Wet resonant noise whose band centre follows f_pts [(t, Hz), ...]."""
    n = n_of(dur)
    ts, fs = zip(*f_pts)
    lfs = np.log(fs)

    def g(t, f):
        fc = np.exp(np.interp(t[:, 0], ts, lfs))[:, None]
        return bp_gain(f, fc, q)

    y = unit(stft_filter(white(n, rng), g, win=512, hop=128))
    amp = env_pts(n, amp_pts or [(0, 0), (0.008, 1), (dur * 0.5, 0.6), (dur, 0)])
    return y * amp


def whoosh(rng, dur, f0, f1, q=1.5, peak=0.4, slope=-3.0):
    """Swept band-pass noise with a swell envelope (swings, take-offs, wind gusts)."""
    n = n_of(dur)
    x = colored(n, rng, slope)
    ratio = f1 / f0

    def g(t, f):
        fc = f0 * ratio ** np.clip(t / dur, 0, 1)
        return bp_gain(f, fc, q)

    y = unit(stft_filter(x, g, win=1024, hop=256))
    amp = env_pts(n, [(0, 0), (dur * peak, 1), (dur, 0)]) ** 1.6
    return y * amp


def cork_pop(rng, f0=300.0, f1=900.0, dur=0.14, noise_db=-6.0):
    """Bottle-cork 'POP': fast upward plop + a short noise snap."""
    n = n_of(dur)
    t = times(n)
    f = f1 + (f0 - f1) * np.exp(-t / 0.012)
    plop = sine(f, n) * env_exp(n, 0.0008, 0.028)
    snap = burst(rng, dur, 2200, 0.8, 0.0035)
    return unit(plop + snap * 10 ** (noise_db / 20))


def crackle(rng, dur, rate, fmin=1500, fmax=6000, glen=(0.002, 0.012), period=None):
    """Poisson field of tiny crackles (twigs/thorns snapping). Evenly spread over
    `dur`; with `period` the events wrap so the result tiles seamlessly."""
    out = zeros(dur + 0.05)
    count = int(rate * dur)
    for _ in range(count):
        t0 = rng.uniform(0, dur)
        L = n_of(rng.uniform(*glen))
        i0 = n_of(t0)
        g = bandpass(white(L + 64, rng), rng.uniform(fmin, fmax), 2.0)[:L]
        g = unit(g) * env_exp(L, 0.0002, L / SR / 4)
        amp = min(1.0, 0.15 * rng.pareto(2.0) + 0.1)
        out[i0 : i0 + L] += g * amp
    if period:
        L = n_of(period)
        tail = out[L:]
        out = out[:L].copy()
        out[: len(tail)] += tail
        return out
    return out[: n_of(dur)]


# --------------------------------------------------------------------------
# tonal / cartoon
# --------------------------------------------------------------------------
def boing(f_base, dur=0.35, wobble=0.14, rate=24.0, rise=0.9, tau=0.11):
    """Cartoon spring 'boing': rising pitch with a decaying fast vibrato."""
    n = n_of(dur)
    t = times(n)
    f = f_base * (1 + rise * (1 - np.exp(-t / 0.05)))
    f = f * (1 + wobble * np.exp(-t / 0.12) * np.sin(2 * np.pi * rate * t))
    x = additive(f, n, [(1, 1.0), (2, 0.4), (3, 0.18), (4, 0.08)])
    return unit(lowpass(x, 3000, 1)) * env_exp(n, 0.002, tau)


def bonk(rng, f0=620.0, f1=380.0, dur=0.4):
    """Hollow cartoon 'BONK' (coconut/wood-block knock with falling pitch)."""
    n = n_of(dur)
    f = glide(n, f0, f1, 0.06)
    ph = phase_of(f)
    t = times(n)
    x = (np.sin(ph) * np.exp(-t / 0.12)
         + 0.5 * np.sin(ph * 1.58) * np.exp(-t / 0.06)
         + 0.25 * np.sin(ph * 2.4) * np.exp(-t / 0.035))
    x = x * np.clip(t / 0.001, 0, 1)
    c = crack(rng, 0.002, 2500)[:n]
    x[: len(c)] += 0.3 * c
    return unit(x)


def slide_whistle(f_pts, dur, vib=(5.0, 0.012), breath_db=-24.0, rng=None):
    n = n_of(dur)
    t = times(n)
    ts, fs = zip(*f_pts)
    f = np.exp(np.interp(t, ts, np.log(fs)))
    f = f * (1 + vib[1] * np.sin(2 * np.pi * vib[0] * t))
    x = additive(f, n, [(1, 1.0), (2, 0.06), (3, 0.03)])
    if rng is not None:
        x = x + 10 ** (breath_db / 20) * unit(bandpass(white(n, rng), 2500, 0.7))
    return unit(x) * env_pts(n, [(0, 0), (0.02, 1), (dur - 0.08, 0.8), (dur, 0)])


VOWELS = {  # (F1, F2, F3) Hz, adult-human reference; scaled up for small critters
    "i": (270, 2290, 3010),
    "e": (530, 1840, 2480),
    "a": (730, 1090, 2440),
    "o": (570, 840, 2410),
    "u": (300, 870, 2240),
    "uh": (520, 1190, 2390),
}


def voice(rng, dur, f0_pts, vowel_pts, scale=1.6, vib=(7.0, 0.015, 0.015),
          breath=0.08, rasp=0.0, amp_pts=None):
    """Formant-additive critter vocalisation (squeaks, yips, death wails).

    f0_pts:    [(t, Hz)] pitch contour
    vowel_pts: [(t, 'i'|'e'|'a'|'o'|'u'|'uh')] formant morph
    vib:       (rate Hz, depth at start, depth at end) -- relative pitch wobble
    rasp:      0..1 random amplitude roughness (strained / hurt quality)
    """
    n = n_of(dur)
    t = times(n)
    ts, fs = zip(*f0_pts)
    f0 = np.exp(np.interp(t, ts, np.log(fs)))
    depth = np.linspace(vib[1], vib[2], n)
    f0 = f0 * (1 + depth * np.sin(2 * np.pi * vib[0] * t)) * (1 + 0.008 * smooth_rand(n, rng, 25))

    vt = [p[0] for p in vowel_pts]
    F = np.array([VOWELS[v] for _, v in vowel_pts], float) * scale
    Ft = [np.interp(t, vt, F[:, i]) for i in range(3)]
    Bw = [Ft[0] * 0.15 + 80, Ft[1] * 0.1 + 100, Ft[2] * 0.08 + 150]
    A = [1.0, 0.8, 0.45]

    ph = phase_of(f0)
    out = np.zeros(n)
    for k in range(1, 48):
        fk = k * f0
        if fk.min() > 15000:
            break
        g = 0.25 * np.ones(n)
        for a, Fi, Bi in zip(A, Ft, Bw):
            g += a / (1 + ((fk - Fi) / (Bi / 2)) ** 2)
        g *= k ** -1.5 * (fk < 15000)
        out += g * np.sin(k * ph)
    out = unit(lowpass(out, 8000, 1))

    if breath > 0:
        tf = np.array(vt)

        def gfn(tt, f):
            tt = tt[:, 0]
            res = np.zeros((len(tt), f.shape[1]))
            for i in range(3):
                Fi = np.interp(tt, tf, F[:, i])[:, None]
                Bi = Fi * 0.2 + 150
                res += A[i] / (1 + ((f - Fi) / (Bi / 2)) ** 2)
            return res

        nz = stft_filter(white(n, rng), gfn, win=1024, hop=256)
        # keep breath noise above the voice's lowest pitch (no rumble under a squeak)
        nz = unit(highpass(nz, 0.7 * min(fs), 2))
        out = out + breath * nz
    if rasp > 0:
        r = lowpass(white(n, rng), 90, 1)
        r = r / (np.max(np.abs(r)) + 1e-12)
        out = out * (1 + rasp * r)
    amp = env_pts(n, amp_pts or [(0, 0), (0.015, 1), (max(0.03, dur - 0.05), 0.75), (dur, 0)])
    return unit(out * amp)


# --------------------------------------------------------------------------
# birds & bugs (ambient)
# --------------------------------------------------------------------------
def whistle(f_pts, dur, amp_pts=None, harm=0.06):
    n = n_of(dur)
    t = times(n)
    ts, fs = zip(*f_pts)
    f = np.exp(np.interp(t, ts, np.log(fs)))
    x = additive(f, n, [(1, 1.0), (2, harm), (3, harm * 0.3)])
    amp = env_pts(n, amp_pts or [(0, 0), (0.02, 1), (dur - 0.04, 0.8), (dur, 0)])
    return x * amp


def bird_feebee(base=3900.0):
    """Two-note 'fee-bee' whistle (chickadee-like)."""
    a = whistle([(0, base), (0.26, base * 0.985)], 0.28)
    b = whistle([(0, base * 0.86), (0.1, base * 0.88), (0.32, base * 0.85)], 0.32)
    gap = np.zeros(n_of(0.06))
    return np.concatenate([a, gap, b * 0.85])


def bird_trill(rng, base=4200.0, notes=14, rate=20.0):
    out = []
    for i in range(notes):
        L = 0.032
        s = whistle([(0, base * 1.15), (L, base * 0.85)], L, [(0, 0), (0.004, 1), (L, 0)])
        amp = 0.6 + 0.4 * np.sin(np.pi * i / notes)
        out.append(s * amp)
        out.append(np.zeros(n_of(1 / rate - L)))
    return np.concatenate(out)


def bird_warble(rng, base=2900.0, dur=0.6):
    n = n_of(dur)
    t = times(n)
    f = base + 520 * np.sin(2 * np.pi * 11 * t) + 320 * smooth_rand(n, rng, 6)
    x = additive(f, n, [(1, 1.0), (2, 0.05)])
    amp = np.clip(0.5 + 0.5 * smooth_rand(n, rng, 9), 0, 1) ** 1.5 * env_pts(n, [(0, 0), (0.03, 1), (dur - 0.05, 1), (dur, 0)])
    return x * amp


def bird_chips(base=3200.0, count=3, spacing=0.13):
    out = []
    for i in range(count):
        out.append(whistle([(0, base), (0.04, base * 1.45)], 0.045, [(0, 0), (0.004, 1), (0.045, 0)]))
        out.append(np.zeros(n_of(spacing - 0.045)))
    return np.concatenate(out)


def dove_coo(base=520.0):
    """Soft 'coo-OOO-oo-oo' (mourning-dove-like) low hoots."""
    notes = [(0.0, 0.32, base * 0.96, base * 1.06, 0.6),
             (0.42, 0.55, base * 1.08, base * 1.0, 1.0),
             (1.08, 0.30, base * 0.97, base * 0.95, 0.7),
             (1.48, 0.32, base * 0.95, base * 0.93, 0.6)]
    out = np.zeros(n_of(1.9))
    for t0, d, fa, fb, a in notes:
        s = whistle([(0, fa), (d * 0.3, fb), (d, fb * 0.98)], d,
                    [(0, 0), (0.06, 1), (d - 0.08, 0.8), (d, 0)], harm=0.18)
        i0 = n_of(t0)
        out[i0 : i0 + len(s)] += s * a
    return out


def cricket_chirp(freq=4700.0, pulses=4, pulse_len=0.012, gap=0.012):
    out = []
    for _ in range(pulses):
        n = n_of(pulse_len)
        s = additive(freq, n, [(1, 1.0), (2, 0.15)]) * np.sin(np.pi * np.arange(n) / n) ** 2
        out.append(s)
        out.append(np.zeros(n_of(gap)))
    return np.concatenate(out)
