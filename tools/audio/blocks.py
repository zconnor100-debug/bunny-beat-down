"""Reusable synthesized sound building blocks (all original, MIT project code).

Every function returns a mono float64 numpy array at dsp.SR. Gains are
roughly unit-peak so recipes can layer them with dB offsets.
"""
import numpy as np

from dsp import (SR, additive, bandpass, bp_gain, colored, db, env_exp, env_pts, fade,
                 fftconvolve, glide, highpass, lowpass, midi_hz, mix, n_of, peak_eq,
                 phase_of, saturate, sine, smooth_rand, stft_filter, times, varispeed,
                 white, zeros)

TAU = 2 * np.pi


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


def snap(rng, fc=3500.0, q=0.9, tau=0.002, dur=0.03):
    """Very short band-passed (~2-5 kHz) noise crack (a gunshot's snap)."""
    n = n_of(dur)
    return unit(bandpass(white(n, rng), fc, q)) * env_exp(n, 0.0002, tau)


def kick(f0, f1, tau_f, tau_a, dur, attack=0.0006, drive=1.0):
    """Tight pitch-gliding sine thump (a gunshot's low-mid 'punch'); drive > 1
    adds odd harmonics so it still reads on small speakers."""
    n = n_of(dur)
    x = sine(glide(n, f0, f1, tau_f), n) * env_exp(n, attack, tau_a)
    return unit(saturate(x, drive)) if drive > 1.0 else x


def lowbody(rng, dur, lo, hi, tau, attack=0.0015, slope=-3.0):
    """Band-limited noise body (lo..hi Hz) with a fast attack and exp decay."""
    n = n_of(dur)
    x = lowpass(highpass(colored(n, rng, slope), lo, 2), hi, 2)
    return unit(x) * env_exp(n, attack, tau)


def struck(rng, modes, dur, exc_ms=1.2, exc_lp=9000.0):
    """Struck-object resonator bank: a short filtered noise strike convolved
    with damped modes [(Hz, decay_s, amp)]. Short decays = wood/shell knock,
    never a ringing bell."""
    n = n_of(dur)
    t = times(n)
    ir = np.zeros(n)
    for f, d, a in modes:
        if f < SR * 0.45:
            ir += a * np.sin(2 * np.pi * f * t) * np.exp(-t / d)
    m = n_of(exc_ms / 1000 * 6)
    exc = lowpass(white(m, rng), exc_lp, 2) * env_exp(m, 0.0002, exc_ms / 1000)
    return unit(fftconvolve(exc, ir)[:n])


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


def wet_grains(rng, dur, count, fmin, fmax, glen=(0.006, 0.02), t_tau=0.05, start=0.0, q=1.4):
    """Dense low-mid noise grains whose band sags downward inside each grain:
    the sticky 'squelch' texture of wet meat (no tonal droplets)."""
    out = np.zeros(n_of(dur))
    for _ in range(count):
        t0 = start + rng.exponential(t_tau)
        L = n_of(rng.uniform(*glen))
        i0 = n_of(t0)
        if i0 + L >= len(out):
            continue
        fc = rng.uniform(fmin, fmax)
        g = bandpass(white(2 * L + 256, rng), fc, q)[128:]
        g = varispeed(g, np.linspace(1.0, 0.7, L))[:L]
        g = unit(g) * np.sin(np.pi * np.arange(len(g)) / len(g)) ** 1.5
        out[i0 : i0 + len(g)] += g * rng.uniform(0.4, 1.0) * np.exp(-(t0 - start) / (t_tau * 2.5))
    return out


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


def twig_snap(rng):
    """Bramble twig snapping: sharp crack + a short dry crunch of wide-band
    noise (no ringing modes, so a field of them crackles instead of clinking)
    (+ splinter)."""
    n = n_of(0.05)
    x = np.zeros(n)
    m = n_of(0.006)
    x[:m] += (unit(highpass(white(m, rng), rng.uniform(1800, 3500), 2))
              * env_exp(m, 0.0001, rng.uniform(0.0006, 0.0015)))
    k = n_of(0.03)
    for fc, q, tau, a in ((rng.uniform(900, 1500), 0.7, rng.uniform(0.003, 0.006), 0.5),
                          (rng.uniform(2500, 4500), 0.9, rng.uniform(0.0015, 0.003), 0.35)):
        x[:k] += a * unit(bandpass(white(k + 256, rng), fc, q)[:k]) * env_exp(k, 0.0002, tau)
    if rng.random() < 0.6:  # splinter
        d = n_of(rng.uniform(0.006, 0.02))
        s = unit(highpass(white(m, rng), 2500, 2)) * env_exp(m, 0.0001, 0.0008)
        x[d:d + m] += 0.6 * s[: n - d]
    a = n_of(0.0002)
    x[:a] *= np.linspace(0, 1, a)
    return unit(x) * env_pts(n, [(0, 1), (0.035, 0.6), (0.05, 0)])


def thorn_scrape(rng, dur):
    """Thorn dragged over bark: stick-slip train of tiny scratchy grains."""
    n = n_of(dur)
    out = np.zeros(n + n_of(0.01))
    rate0 = rng.uniform(35, 80)
    fc = rng.uniform(2600, 5200)
    tt = 0.0
    while tt < dur:
        L = n_of(rng.uniform(0.0012, 0.004))
        i0 = n_of(tt)
        g = unit(bandpass(white(L + 128, rng), fc * rng.uniform(0.8, 1.25), 2.5)[:L]) * env_exp(L, 0.0002, L / SR / 3)
        out[i0:i0 + L] += g * rng.uniform(0.4, 1.0)
        tt += 1.0 / (rate0 * rng.uniform(0.6, 1.5))
    out = out[:n]
    return out * env_pts(n, [(0, 0), (dur * 0.3, 1), (dur * 0.7, 0.7), (dur, 0)])


# --------------------------------------------------------------------------
# mechanical foley: dense 'noise-modal' bodies, hits through them, friction
# --------------------------------------------------------------------------
def noise_ir(rng, octs, peaks=(), dur=0.25):
    """Dense 'noise-modal' body: a complex metal/polymer assembly has so many
    modes that its impulse response is coloured noise whose decay depends on
    frequency. octs = [(octave centre Hz, gain dB, tau s)] (interpolated in
    log-frequency with raised-cosine crossovers), peaks = [(Hz, Q, gain dB,
    tau s)]: narrow resonant noise bands -- the part's characteristic
    'clink'/'clack' colour, rough like a real ring instead of a pure sine.
    Pass a fixed-seed rng so every variant uses the same body."""
    r = rng
    n = n_of(dur)
    t = times(n)
    W = np.fft.rfft(r.standard_normal(n))
    f = np.maximum(np.fft.rfftfreq(n, 1 / SR), 1.0)
    lf = np.log2(f)
    cs = np.log2([o[0] for o in octs])
    ir = np.zeros(n)
    for k, (fc, g, tau) in enumerate(octs):
        # triangular-in-log2 weights through neighbouring centres (sum to 1)
        lo = cs[k - 1] if k > 0 else cs[k] - 1.0
        hi = cs[k + 1] if k + 1 < len(cs) else cs[k] + 1.0
        w = np.where(lf <= cs[k], (lf - lo) / (cs[k] - lo), (hi - lf) / (hi - cs[k]))
        w = np.clip(w, 0, 1)
        if k == 0:
            w = np.where(lf < cs[k], np.clip(lf - (cs[k] - 1.0), 0, 1), w)
        if k == len(octs) - 1:
            w = np.where(lf > cs[k], 1.0, w)
        w = 0.5 - 0.5 * np.cos(np.pi * w)
        ir += np.fft.irfft(W * w, n) * db(g) * np.exp(-t / tau)
    for fc, q, g, tau in peaks:
        p = bandpass(r.standard_normal(n), fc, q)
        ir += p / (np.std(p) + 1e-12) * np.std(ir) * db(g) * np.exp(-t / tau)
    return ir / (np.max(np.abs(ir)) + 1e-12)


def modal_hit(rng, ir, hard=0.0002, rebounds=((0.005, -9), (0.013, -15)), tick_db=-6.0,
              tick_fc=3500.0, jitter=0.25):
    """Hard contact through a modal body (noise_ir): a main noise-burst strike
    plus a few smaller rebounds (real mechanisms chatter), and the dry contact tick."""
    m = n_of(hard * 12)
    span = max([0.0] + [d for d, _ in rebounds]) * (1 + jitter) + 0.004
    exc = np.zeros(n_of(span) + m)
    hits = [(0.0, 0.0)] + [(d * rng.uniform(1 - jitter, 1 + jitter), g + rng.uniform(-2, 2))
                           for d, g in rebounds]
    for d, g in hits:
        i0 = n_of(d) if d > 0 else 0
        exc[i0: i0 + m] += white(m, rng) * np.exp(-times(m) / hard) * db(g)
    y = unit(fftconvolve(exc, ir))
    tick = crack(rng, hard * 1.5, tick_fc)
    return unit(mix(0, (y, 0, 0), (tick, 0, tick_db)))


def scrape(rng, dur, f_lo, f_hi, ir=None, grains=350.0, rough=0.75,
           shape=((0, 0), (0.25, 1), (0.8, 0.8), (1, 0)), ir_db=-6.0, grain_count=None):
    """Friction slide (metal or polymer on metal): band-limited noise with
    stick-slip amplitude roughness (`grains` Hz), plus sparse micro-impacts
    through the part's modal body `ir`."""
    n = n_of(dur)
    nz = highpass(lowpass(white(n, rng), f_hi, 2), f_lo, 2)
    m = np.abs(lowpass(white(n, rng), grains, 1))
    m /= np.max(m) + 1e-12
    y = unit(nz) * ((1 - rough) + rough * m)
    if ir is not None:
        k = grain_count if grain_count is not None else int(grains * 0.08 * dur) + 2
        imp = np.zeros(n)
        idx = rng.integers(0, n, k)
        imp[idx] = rng.uniform(0.2, 1.0, k) * rng.choice([-1.0, 1.0], k)
        tex = fftconvolve(imp, ir)[:n]
        y = y + db(ir_db) * unit(tex)
    ts, vs = zip(*shape)
    env = np.interp(times(n), np.array(ts) * dur, vs)
    return unit(y) * env


def shk(rng, dur=0.03, f_lo=2500.0, f_hi=12000.0, tau=0.008):
    """Broadband friction/air 'shk' riding on a hard stop (metal parts grinding
    to a halt): makes a clack read as 'chk' instead of a pitched 'tok'."""
    n = n_of(dur)
    x = highpass(lowpass(white(n, rng), f_hi, 2), f_lo, 2)
    m = np.abs(lowpass(white(n, rng), 600.0, 1))
    x = unit(x) * (0.45 + 0.55 * m / (np.max(m) + 1e-12))
    return unit(x) * np.exp(-times(n) / tau) * np.clip(times(n) / 0.0005, 0, 1)


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


def harp_note(freq, dur, rng, tau=None, pos=0.42, roll=1.75, damp=3.5, attack=0.0025,
              finger_db=-30.0, inharm=4e-5, bloom=0.22):
    """One plucked concert-harp string (modal synthesis, exactly in tune).

    tau     decay time constant of the fundamental (s); default follows the real
            instrument (bass strings ring for seconds, top strings ~0.3 s)
    pos     pluck position along the string (0.5 = middle: mellow, odd harmonics)
    roll    harmonic amplitude roll-off exponent (2 = ideal soft pluck)
    damp    extra damping of high partials (1/s at 1 kHz, grows with f^1.5)
    bloom   share of the slower, slightly detuned second string polarisation
    """
    n = n_of(dur)
    t = times(n)
    if tau is None:
        tau = float(np.clip(1.5 * (220.0 / freq) ** 0.7, 0.18, 3.0))
    out = np.zeros(n)
    for k in range(1, 40):
        fk = k * freq * np.sqrt(1.0 + inharm * k * k)
        if fk > SR * 0.42:
            break
        a = abs(np.sin(np.pi * k * pos)) / k ** roll
        if a < 2e-4:
            continue
        rate = 1.0 / tau + damp * (fk / 1000.0) ** 1.5
        det = 1.0 + rng.uniform(1.5e-4, 5e-4)
        out += a * ((1 - bloom) * np.sin(TAU * fk * t) * np.exp(-t * rate)
                    + bloom * np.sin(TAU * fk * det * t + rng.uniform(0, 0.4)) * np.exp(-t * rate * 0.62))
    atk = n_of(attack)
    out[:atk] *= 0.5 - 0.5 * np.cos(np.linspace(0, np.pi, atk))
    out = unit(out)
    if finger_db > -90:  # the fingertip leaving the gut string
        m = n_of(0.006)
        nz = bandpass(white(m + 256, rng), float(np.clip(freq * 2.5, 900, 4000)), 1.4)[:m]
        out[:m] += unit(nz) * env_exp(m, 0.0004, 0.0015) * 10 ** (finger_db / 20)
    return fade(out, 0.0, min(dur * 0.25, 0.12))


def harp_roll(notes, rng, dur, gap, body=True, **kw):
    """Rolled harp chord / arpeggio: notes = [(midi, gain_db), ...] spaced `gap` s."""
    layers = []
    for i, (m, g) in enumerate(notes):
        layers.append((harp_note(midi_hz(m), dur - i * gap, rng, **kw), i * gap, g))
    x = mix(dur, *layers)
    if body:  # soundboard: warm low-mid bloom, slightly hollow box
        x = peak_eq(x, 210.0, 3.0, 0.9)
        x = peak_eq(x, 520.0, 1.5, 1.2)
    return x


def flute_line(rng, notes, rel=0.09, breath_db=-13.0, hiss_db=-24.0, chiff_db=-11.0,
               vib_rate=5.4, vib_depth=0.008, trem=0.18, glide=0.012,
               tone=(1.0, 0.34, 0.15, 0.06, 0.028, 0.012)):
    """Legato wooden-flute phrase.

    notes = [(t0, dur, midi, tongued, amp), ...] back to back (t0 ascending).
    Tongued notes get a breath chiff, a pitch scoop and an amplitude re-attack;
    slurred notes just change finger (tiny dip, quick glide). Notes longer than
    0.22 s grow a delayed vibrato (pitch + breath-pressure tremolo).
    """
    end = max(t0 + d for t0, d, *_ in notes)
    n = n_of(end + rel + 0.02)
    t = times(n)
    logf = np.zeros(n)
    amp = np.zeros(n)
    vib_env = np.zeros(n)
    scoop = np.zeros(n)
    onset = np.zeros(n)
    on_times = []
    for j, (t0, d, m, tongued, a) in enumerate(notes):
        i0, i1 = n_of(t0), n_of(t0 + d)
        last = j == len(notes) - 1
        if last:
            i1 = n
        logf[i0:i1] = np.log2(midi_hz(m))
        seg = t[i0:i1] - t0
        if tongued:
            e = np.clip(seg / 0.028, 0, 1) ** 0.8
            on_times.append(t0)
            sc = np.exp(-seg / 0.018)
            scoop[i0:i1] = np.maximum(scoop[i0:i1], sc)
            onset[i0:i1] = np.maximum(onset[i0:i1], np.exp(-seg / 0.025))
        else:
            e = 1 - 0.14 * np.exp(-((seg - 0.004) / 0.006) ** 2)  # finger change
        if last:
            e = e * np.interp(seg, [0, d, d + rel], [1.0, 1.0, 0.0])
        amp[i0:i1] = a * e
        if d > 0.22:
            vib_env[i0:i1] = np.clip((seg - 0.11) / 0.16, 0, 1)
    # first note starts at its own pitch (the zero area before it is silent anyway)
    first = n_of(notes[0][0])
    logf[:first] = logf[first]
    # portamento between notes, then breath scoop on tongued attacks (-30 cents)
    w = max(1, n_of(glide))
    logf = np.convolve(np.pad(logf, (w, w), mode="edge"), np.ones(w) / w, mode="same")[w:-w]
    logf = logf - 0.025 * scoop
    vib = np.sin(TAU * vib_rate * t + 0.3 * smooth_rand(n, rng, 1.5))
    wander = 0.0012 * smooth_rand(n, rng, 3.0)
    f = 2.0 ** logf * (1 + vib_depth * vib_env * vib + wander)
    env = amp * (1 + trem * vib_env * np.sin(TAU * vib_rate * t + 0.9))
    env = np.convolve(env, np.ones(n_of(0.004)) / n_of(0.004), mode="same")

    ph = phase_of(f)
    x = np.zeros(n)
    for k, wk in enumerate(tone, start=1):
        if k * f.max() > SR * 0.42:
            break
        bright = np.clip(env, 1e-4, None) ** (0.45 * (k - 1))
        boost = 1 + (1.6 * onset if k == 2 else 0.6 * onset if k == 3 else 0)  # overblown edge of a tongued attack
        x += wk * bright * boost * np.sin(k * ph + 0.4 * k)
    x *= env

    # pitch-tracked breath turbulence around the fundamental and 2nd harmonic
    fi = f

    def g(tt, fr):
        i = np.clip((tt[:, 0] * SR).astype(int), 0, n - 1)
        fc = fi[i][:, None]
        return bp_gain(fr, fc, 7.0) + 0.55 * bp_gain(fr, 2 * fc, 7.0) + 0.25 * bp_gain(fr, 3 * fc, 6.0)

    turb = unit(stft_filter(white(n, rng), g, win=1024, hop=256)) * env
    hiss = unit(highpass(bandpass(white(n, rng), 2800, 0.6), 1200, 2)) * env ** 1.5
    chiffs = np.zeros(n)
    for t0 in on_times:
        m_ = n_of(0.03)
        i0 = n_of(t0)
        c_ = unit(bandpass(white(m_ + 256, rng), 3200, 1.1)[:m_]) * env_exp(m_, 0.0008, 0.006)
        chiffs[i0:i0 + m_] += c_[: n - i0]
    tone_rms = np.sqrt(np.mean(x[x != 0] ** 2)) + 1e-12
    y = (x / tone_rms
         + turb * 10 ** (breath_db / 20) / (np.sqrt(np.mean(turb ** 2)) + 1e-12)
         + hiss * 10 ** (hiss_db / 20) / (np.sqrt(np.mean(hiss ** 2)) + 1e-12)
         + chiffs * 10 ** (chiff_db / 20) * 3.0)
    return unit(y)


def _tick_click(rng, f_scale, body_hz, case_amt, n):
    """One contact of a clock tick: a crack of high-passed noise, a bright
    noise 'tk' and a wide-band (low-Q) woody noise knock, all gone within a few
    ms -- no resonant modes, so it never rings or sounds like a note."""
    x = np.zeros(n)
    m = n_of(0.004)
    x[:m] += 0.6 * unit(highpass(white(m, rng), 2500 * f_scale, 2)) * env_exp(m, 0.0001, 0.0006)
    k = n_of(0.03)
    x[:k] += 0.3 * unit(bandpass(white(k + 256, rng), 3600 * f_scale, 1.0)[:k]) * env_exp(k, 0.0001, 0.0015)
    for fc, g, tau in ((body_hz, 1.3, 0.005), (body_hz * 0.42, 0.8, 0.006)):   # the woody 'tock'
        knock = bandpass(white(k + 256, rng), fc * rng.uniform(0.95, 1.05), 0.8)[:k]
        x[:k] += g * case_amt * unit(knock) * env_exp(k, 0.0002, tau)
    a = n_of(0.00025)
    x[:a] *= np.linspace(0, 1, a)
    return x


def clock_tick(rng, f_scale=1.0, body_hz=1100.0, case_amt=1.0):
    """Dry clock 'tick' made only of noise: a small unlock click, the drop
    click ~10 ms later and a faint settle (see _tick_click)."""
    n = n_of(0.06)
    gap = rng.uniform(0.0085, 0.0115)
    return unit(mix(0.06,
                    (_tick_click(rng, f_scale * 1.06, body_hz, case_amt * 0.4, n), 0, -9),
                    (_tick_click(rng, f_scale, body_hz, case_amt, n), gap, 0),
                    (_tick_click(rng, f_scale * 0.95, body_hz, case_amt * 0.5, n),
                     gap + rng.uniform(0.012, 0.016), -18)))


VOWELS = {  # (F1, F2, F3) Hz, adult-human reference; scaled up for small critters
    "i": (270, 2290, 3010),
    "e": (530, 1840, 2480),
    "a": (730, 1090, 2440),
    "o": (570, 840, 2410),
    "u": (300, 870, 2240),
    "uh": (520, 1190, 2390),
    "ae": (660, 1720, 2410),
    "aw": (640, 1000, 2400),
    "oo": (380, 950, 2300),
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


def _lpn(r, n, fc):
    """Low-passed white noise in [-1, 1] (random control signal)."""
    return unit(lowpass(white(n, r), fc, 2))


def _curve(t, pts, log=False):
    ts, vs = zip(*pts)
    if log:
        return np.exp(np.interp(t, ts, np.log(vs)))
    return np.interp(t, ts, vs)


def glottal_pulses(r, n, rate_pts, tau=0.004, jit=0.3):
    """Irregular glottal-pulse amplitude train in [0, 1] (vocal fry / creak)."""
    t = times(n)
    rate = _curve(t, rate_pts, log=True) * (1 + jit * _lpn(r, n, 30))
    ph = np.cumsum(rate) / SR
    idx = np.nonzero(np.diff(np.floor(ph)) > 0)[0] + 1
    imp = np.zeros(n)
    imp[idx] = r.uniform(0.55, 1.0, len(idx))
    L = n_of(tau * 6)
    y = fftconvolve(imp, np.exp(-times(L) / tau))[:n]
    return y / (y.max() + 1e-12)


def critter_voice(r, dur, f0_pts, vowel_pts, scale=1.3, tilt=1.25, sub_pts=None, jitter=0.025,
                  shimmer=0.15, trill=None, fry_pts=None, fry_rate=((0, 60),), breath=0.12,
                  hoarse=0.3, vib=None, amp_pts=None, flutter=0.03, fmax=6500.0, drive=1.6):
    """Formant-additive small-animal vocalisation with grit (deeper and rougher
    than voice(): fox / raccoon / squirrel rather than a whistly squeak).

    f0_pts / vowel_pts: pitch contour [(t, Hz)] and formant morph [(t, vowel)]
    scale:     formant scale vs an adult human (1.3 = fox/raccoon-sized throat)
    sub_pts:   [(t, 0..1)] subharmonic (period-doubling) amount: growl / roughness
    jitter:    fast random pitch wander;  shimmer: fast random amplitude wander
    trill:     (rate Hz, [(t, depth)]) amplitude chirr ("rrrr")
    fry_pts:   [(t, 0..1)] blend toward irregular glottal pulses (creak / grunt)
    vib:       (rate Hz, depth at start, depth at end)
    breath:    steady aspiration noise through the formants
    hoarse:    pitch-synchronous (pulsed) formant noise: a hoarse, raspy throat
    fmax:      soft upper limit of the voiced spectrum (no whistly highs)
    drive:     tanh saturation of the voiced part (strain)
    """
    n = n_of(dur)
    t = times(n)
    f0 = _curve(t, f0_pts, log=True)
    if vib:
        f0 = f0 * (1 + np.linspace(vib[1], vib[2], n) * np.sin(2 * np.pi * vib[0] * t))
    if jitter:
        f0 = f0 * (1 + jitter * _lpn(r, n, 90))
    vt = [p[0] for p in vowel_pts]
    F = np.array([VOWELS[s] for _, s in vowel_pts], float) * scale
    Ft = [np.interp(t, vt, F[:, i]) for i in range(3)]
    if flutter:
        Ft = [Fi * (1 + flutter * _lpn(r, n, 10)) for Fi in Ft]
    Bw = [Ft[0] * 0.2 + 90, Ft[1] * 0.12 + 110, Ft[2] * 0.1 + 160]
    A = (1.0, 0.7, 0.35)

    def fgain(fk):
        g = 0.05 + sum(a / (1 + ((fk - Fi) / (Bi * 0.5)) ** 2) for a, Fi, Bi in zip(A, Ft, Bw))
        return g / (1 + (fk / fmax) ** 8) * (fk < 19000)

    ph = phase_of(f0)
    out = np.zeros(n)
    kmax = min(160, int(2.2 * fmax / f0.min()) + 1)
    for k in range(1, kmax + 1):
        out += fgain(k * f0) * k ** -tilt * np.sin(k * ph)
    if sub_pts:
        sub = _curve(t, sub_pts)
        for k in range(1, kmax + 1):
            h = k - 0.5
            out += sub * fgain(h * f0) * h ** -tilt * np.sin(h * ph)
    out = unit(out)
    if drive:
        out = saturate(out, drive)

    amp = np.ones(n)
    if shimmer:
        amp *= 1 + shimmer * _lpn(r, n, 70)
    if trill:
        rate, dpts = trill
        d = _curve(t, dpts)
        tph = 2 * np.pi * np.cumsum(rate * (1 + 0.08 * _lpn(r, n, 6))) / SR
        amp *= 1 - d * (0.5 - 0.5 * np.cos(tph))
    if fry_pts:
        fa = _curve(t, fry_pts)
        amp *= (1 - fa) + fa * glottal_pulses(r, n, fry_rate)
    out = out * amp

    if breath > 0 or hoarse > 0:
        tf = np.array(vt, float)

        def gfn(tt, f):
            tt = tt[:, 0]
            res = np.zeros((len(tt), f.shape[1]))
            for i in range(3):
                Fi = np.interp(tt, tf, F[:, i])[:, None]
                Bi = Fi * 0.25 + 180
                res += A[i] / (1 + ((f - Fi) / (Bi / 2)) ** 2)
            return res

        nz = stft_filter(white(n, r), gfn, win=1024, hop=256)
        nz = unit(lowpass(highpass(nz, 300, 2), 7000, 2))
        glot = (0.5 + 0.5 * np.cos(ph)) ** 4  # one noise puff per glottal cycle
        nz = nz * (breath * (1 + shimmer * _lpn(r, n, 70)) + hoarse * glot * amp)
        out = unit(out) + nz
    env = env_pts(n, amp_pts or [(0, 0), (0.012, 1), (max(0.03, dur - 0.06), 0.7), (dur, 0)])
    # saturation intermodulation leaves junk under f0/2: nothing useful below 80 Hz
    return unit(highpass(lowpass(out * env, fmax * 1.15, 2), 80, 2))


def tongue_click(r, fc=2200.0, q=1.2, tau=0.003):
    """Tongue/teeth 'k' click that starts a chitter syllable."""
    return burst(r, 0.03, fc, q, tau, attack=0.0004)


def chitter(r, starts, f0s, dur=0.05, vowels=("ae", "uh"), click_db=-9.0, gains=None, **kw):
    """Quick 'ak-ak-ak' syllable run (squirrel / raccoon chatter)."""
    layers = []
    for i, (t0, f) in enumerate(zip(starts, f0s)):
        s = critter_voice(r, dur, [(0, f * 0.85), (0.012, f), (dur, f * 0.72)],
                          [(0, vowels[0]), (dur, vowels[1])],
                          amp_pts=[(0, 0), (0.004, 1), (dur * 0.45, 0.65), (dur, 0)], **kw)
        g = gains[i] if gains else 0.0
        layers += [(s, t0, g), (tongue_click(r, 2000 + 400 * r.random()), t0, g + click_db)]
    return mix(starts[-1] + dur, *layers)


def exhale(r, dur=0.35, lp=1600.0, tau=0.12):
    """Last breath out: soft low 'hhhh'."""
    n = n_of(dur)
    x = lowpass(highpass(colored(n, r, -2), 250, 2), lp, 2)
    return unit(x) * env_pts(n, [(0, 0), (0.04, 1), (dur, 0)]) * env_exp(n, 0.0, tau * 3)


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
