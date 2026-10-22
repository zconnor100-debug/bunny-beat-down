"""Sound recipes: one function per manifest key.

Each recipe is registered with @recipe(key, variants, loud, src) and is called
once per variant as fn(c, v) -> mono numpy array, where `c` is the build
context (see build_audio.py):

    c.k(pack, stem, speed=1.0, start=0.0, dur=None)  -> Kenney CC0 clip,
        peak-normalised, optionally varispeed-resampled and sliced
    c.o(oga_id, path)                                 -> whole OpenGameArt
        recording (an entry of sources.OGA), peak-normalised
    c.rng                                             -> seeded numpy Generator

`loud` is the target short-term (50 ms) RMS in dBFS used by the normaliser,
which gives the game a consistent starting mix (weapons loud, UI quiet).
`src` is "synth" (100 % original), "kenney" (processed Kenney only) or
"mixed" (Kenney / OpenGameArt layers + original synth layers); it drives the
credits.

Registering a key again replaces the earlier recipe in place (same manifest
position). build_audio.py imports any tools/audio/recipes_wip_*.py after this
module, so a sound can be reworked in a scratch module without touching this
file; see "Iterating on sounds" in README.md.
"""
import zlib

import numpy as np
from numpy.lib.stride_tricks import sliding_window_view

import blocks as B
from dsp import (SR, additive, bandpass, bell, bp_gain, causal_hp, circ_compress, circ_filter,
                 circ_reverb, circ_stft, colored, compress, db, env_exp, env_pts, fade,
                 fold_circular, glide, highpass, hp_mag, k_weight, limit, loudness_db, lowpass,
                 lp_mag, make_loop, midi_hz, mix, n_of, pad_to, peak_eq, phase_of, pluck, reverb,
                 rms_env, saturate, saw_bl, shape_oversampled, shelf, sine, smooth_rand, softclip,
                 squash, stft_filter, times, varispeed, white)


RECIPES = []


def recipe(key, variants=1, loud=-14.0, src="mixed", loop=False):
    def deco(fn):
        entry = dict(key=key, variants=variants, loud=loud, src=src, loop=loop, fn=fn)
        # re-registering a key replaces it in place (recipes_wip_*.py overrides)
        for i, r in enumerate(RECIPES):
            if r["key"] == key:
                RECIPES[i] = entry
                break
        else:
            RECIPES.append(entry)
        return fn
    return deco


def _pick(seq, v):
    return seq[v % len(seq)]


# ==========================================================================
# WEAPONS -- real firearm recordings + synth transient/boom/tail shaping,
#            with only a faint carrot crunch underneath
# ==========================================================================
# Real-firearm core layers come from The Free Firearm Sound Library (CC0, via
# OpenGameArt): 96 kHz near-perspective recordings, several takes per file.
FF = "free-firearm-sound-library"
FFP = "Prepared SFX Library/"
PRE = 0.004  # every take() starts 4 ms before the shot's onset


def take(x, t, dur, hold=0.1, tau=0.2):
    """Cut one shot out of a multi-take recording.

    Finds the exact onset within +-30 ms of `t` (s), keeps PRE before it and
    `dur` after, and shapes the tail: unity for `hold` s, then an exponential
    fade with time constant `tau` (shortens long outdoor tails to taste).
    """
    i = n_of(t)
    w0, w1 = max(0, i - n_of(0.03)), min(len(x), i + n_of(0.03))
    seg = np.abs(x[w0:w1])
    on = w0 + int(np.argmax(seg > 0.2 * seg.max()))
    a = max(0, on - n_of(PRE))
    y = x[a : a + n_of(PRE + dur)].copy()
    tt = times(len(y))
    y *= np.where(tt < PRE + hold, 1.0, np.exp(-(tt - PRE - hold) / tau))
    return y / (np.max(np.abs(y)) + 1e-12)


def _rolling_echoes(x, rng, taps):
    """Forest slap-back: delayed, progressively darker copies (delay_s, gain_db, lowpass_hz)."""
    out = x.copy()
    for d, g, lp in taps:
        out = mix(0, (out, 0, 0), (lowpass(x, lp, 2), d, g))
    return out


# --------------------------------------------------------------------------
# gunshot punch kit: a harder, denser head without turning the crack down
# --------------------------------------------------------------------------
# B.kick / B.snap / B.lowbody add a tight thump, crack and noise body; agree()
# flips a layer's polarity so it reinforces (not cancels) the recording's own
# low lobe; head_bus() is a transient-designer 'sustain' on the band-limited
# body (+ optional parallel compression, gated off before the onset);
# clamp_body() / hit_clamp() keep the hit no later than the original's;
# head_sub_fix() causally removes the sub-sonic swing a saturated low hit
# leaves (finish()'s zero-phase 35 Hz high-pass would answer it with an offset
# BEFORE the shot); splice() puts a new head on an original render's tail at
# its exact old level; fit() pre-gates the onset, then soft-clips / limits
# just enough that finish() reaches the recipe's loudness with the peak at
# about -1.3 dBFS instead of the normaliser's tanh knee squashing the crack.
GUN_CEIL = -1.0      # build_audio.finish() ceiling
FIT_MARGIN = 0.3     # dB of headroom left for finish()'s 35 Hz high-pass / encoder
CLIP_MARGIN = 0.55   # the same for soft-clipped (flat-topped) heads: Vorbis overshoots them more


def agree(base, layer, off, lp=300.0, win=0.03):
    """Return +layer or -layer, whichever reinforces base's low end (< lp Hz) in the
    first `win` s after `off` instead of cancelling it (thump layers vs the
    recording's own low lobe)."""
    n = len(layer)
    i0 = n_of(off)
    b = lowpass(np.pad(base, (0, max(0, i0 + n - len(base))))[i0:i0 + n], lp, 2)
    k = lowpass(layer, lp, 2)
    m = n_of(win)
    return layer if np.dot(b[:m], k[:m]) >= 0 else -layer


def crack_lift(x, on, gain_db, fc=2000.0, until=0.02, fade=0.01, lead=0.0005):
    """Lift the recording's own crack: + gain_db above fc Hz for `until` s after the
    onset (raised-cosine release over `fade` s); the time window (ramping in over
    the `lead` s before the onset) also removes the zero-phase high-pass's
    pre-ringing."""
    t = times(len(x)) - on
    w = np.clip((t + lead) / lead, 0, 1) * np.clip(1 - (t - until) / fade, 0, 1)
    w = 0.5 - 0.5 * np.cos(np.pi * w)
    return x + (db(gain_db) - 1) * highpass(x, fc, 2) * w


def head_bus(x, on, boost_db=6.0, hp=250.0, hold=0.03, fade=0.04, drive=1.5,
             smash_db=None, thr=-24.0, ratio=3.0, clamp_db=0.0, sat_until=None, lp=None):
    """Make the head hit harder at the same peak (transient-designer 'sustain').

    The body after the first ~1 ms (band-limited to `hp`..`lp` Hz, so the punch
    band gets denser rather than the sub boom or the fizz) is raised by `boost_db`
    for `hold` s, easing back to unity over `fade` s; the transient itself is
    untouched and the body keeps its natural decay shape. Optionally a gentle
    parallel compressor (`smash_db`, `thr`, `ratio`) adds more density; it is
    gated off before the onset, so its make-up gain cannot lift the zero-phase
    filters' pre-ringing into an audible pre-swell. A tanh glues it all; with
    `sat_until` (s after the onset) the tanh is crossfaded to its small-signal
    linear gain after that, so a long tail keeps its exact decay shape.
    """
    xh = highpass(x, hp, 2) if hp else x
    if lp:
        xh = lowpass(xh, lp, 2)
    t = times(len(x)) - on
    up = np.clip((t - 0.0006) / 0.0025, 0, 1)
    down = np.clip(1 - (t - hold) / fade, 0, 1)
    shape = (0.5 - 0.5 * np.cos(np.pi * up)) * (0.5 - 0.5 * np.cos(np.pi * down))
    out = x + (db(boost_db) - 1) * xh * shape
    if smash_db is not None:
        y = compress(xh, thr, ratio, 0.0002, 0.012, win=0.002)
        i0, i1 = n_of(on), n_of(on + hold)
        y *= np.max(rms_env(x)) / (np.median(rms_env(y)[i0:i1]) + 1e-12)
        pre = np.clip((t + 0.0002) / 0.0002, 0, 1)      # nothing before the shot
        out = out + db(smash_db) * y * pre * (0.5 - 0.5 * np.cos(np.pi * down))
    pk = np.max(np.abs(out))
    sat = saturate(out / pk, drive) * pk
    if sat_until is not None:
        lin = out * drive / np.tanh(drive)
        u = np.clip((t - sat_until) / 0.03, 0, 1)
        u = 0.5 - 0.5 * np.cos(np.pi * u)
        sat = sat * (1 - u) + lin * u
    return clamp_body(sat, on, clamp_db) if clamp_db is not None else sat


def hit_time(x, on=PRE, within_db=1.0, win=0.001, span=0.03):
    """Time (s after `on`) at which the 1 ms envelope of the 35 Hz high-passed
    signal (as finish() will see it) first comes within `within_db` of its max over
    the first `span` s: how late the shot's loudest moment arrives."""
    e = rms_env(highpass(x, 35, 2), win)[n_of(on): n_of(on + span)]
    return np.argmax(e >= np.max(e) * db(-within_db)) / SR


def head_sub_fix(x, end=0.08, fade=0.03, fc=30.0, tail=0.15):
    """Take the sub-`fc` Hz content out of the head (first `end` s, tapering out over
    `fade` s) with a causal high-pass. Saturating / clipping a big asymmetric low
    hit leaves a slow sub-sonic swing that finish()'s zero-phase 35 Hz high-pass
    would otherwise answer with a step-like offset BEFORE the shot (an audible-looking
    pre-swell); removed causally here, nothing is left for it to pre-ring. Past
    `end + fade + tail` s the signal is untouched (the causal filter's own ring-out
    has decayed far below audibility by then)."""
    t = times(len(x))
    m = np.clip(1 - (t - end) / fade, 0, 1)
    m = 0.5 - 0.5 * np.cos(np.pi * m)
    k = min(len(x), n_of(end + fade + tail))
    e = x[:k] * m[:k]
    out = x.copy()
    out[:k] += causal_hp(e, fc) - e
    return out


def hit_clamp(x0, margin_db, on=PRE, min_head=0.003, margin5_db=None):
    """A fit() post-step that keeps the new head from peaking later than the
    original render x0 did: after x0's time-to-within-1-dB (at least `min_head`),
    the 1 ms envelope (of the 35 Hz high-passed signal, as finish() will see it)
    is clamped to the level the new head reached by then, + |margin_db| dB. With
    `margin5_db` the same is done for the 5 ms envelope after x0's own 5 ms
    envelope peak (so a heavy low body cannot build up to a later, bigger peak)."""
    head = max(hit_time(x0, on), min_head) + 0.0005
    e5 = rms_env(highpass(x0, 35, 2), 0.005)[n_of(on): n_of(on + 0.03)]
    head5 = np.argmax(e5) / SR + 0.001

    def post(y):
        yh = highpass(y, 35, 2)
        y = clamp_body(y, on, margin_db, head=head, win=0.001, look=0.0006, detect=yh)
        if margin5_db is not None:
            y = clamp_body(y, on, margin5_db, head=head5, win=0.005, look=0.0025, detect=highpass(y, 35, 2))
        return y
    return post


def clamp_body(x, on, margin_db=0.0, head=0.004, win=0.005, look=0.0025, detect=None):
    """Keep the transient the loudest moment: after the first `head` s, duck any
    5 ms window that would come within `margin_db` of the transient's level (so
    the envelope still peaks at the shot, i.e. a fast attack, however dense the
    body is). `detect` (default x) is the signal the envelopes are measured on."""
    e = rms_env(x if detect is None else detect, win)
    i0, i1 = n_of(on), n_of(on + head)
    e0 = np.max(e[i0:i1]) * db(-margin_db)
    g = np.minimum(1.0, e0 / e)
    g[:i1] = 1.0
    L = n_of(look)
    gmin = sliding_window_view(np.pad(g, L, constant_values=1.0), 2 * L + 1).min(axis=1)
    w = np.hanning(2 * L + 3)[1:-1]
    w /= w.sum()
    return x * np.convolve(np.pad(gmin, L, mode="edge"), w, mode="valid")


def pregate(x, on, a=0.0015, b=0.0003):
    """Silence the pre-ringing that zero-phase FFT filters smear in front of the
    shot: unity from `b` s before the onset, raised-cosine down to zero `a` s
    before it. Keeps the true leading edge, makes the attack crisp again."""
    t = times(len(x)) - on
    u = np.clip((t + a) / (a - b), 0, 1)
    return x * (0.5 - 0.5 * np.cos(np.pi * u))


def fit(x, loud, ceiling=GUN_CEIL, margin=FIT_MARGIN, on=PRE, gate=(0.0015, 0.0003), clip=0.0, knee=0.7,
        post=None):
    """Pre-gate the onset, then limit the peaks just enough that finish()/normalize()
    reaches `loud` with the peak at ceiling - margin (so its tanh knee never touches
    the transient). Peaks and loudness are judged on the 35 Hz high-passed signal
    finish() will see, but the signal is returned un-filtered so finish() high-passes
    it exactly once, as before. With `clip` (dB, at most) the overshoot is first
    taken off with the soft clipper, so less look-ahead limiting (which turns the
    whole crack down) is needed. `post` (a function of the signal) is re-applied
    after every peak-reduction step (e.g. a body clamp that must still hold on the
    clipped result)."""
    if on is not None:
        x = pregate(x, on, *gate)
    if post is not None:
        x = post(x)
    done = 0.0
    for _ in range(12 if clip > 0 else 0):
        xh = highpass(x, 35, 2)
        allowed = ceiling - margin - (loud - loudness_db(xh))
        over = 20 * np.log10(np.max(np.abs(xh)) + 1e-12) - allowed
        step = min(over + 0.01, clip - done)
        if over <= 0.02 or step <= 0.02:
            break
        x = softclip(x, step, knee)
        if post is not None:
            x = post(x)
        done += step
    for _ in range(12):
        xh = highpass(x, 35, 2)
        allowed = ceiling - margin - (loud - loudness_db(xh))
        over = 20 * np.log10(np.max(np.abs(xh)) + 1e-12) - allowed
        if over <= 0.02:
            break
        # limiting also lowers the loudness, so step past the overshoot
        x = limit(x, 20 * np.log10(np.max(np.abs(x)) + 1e-12) - min(1.6 * over, over + 1.0))
        if post is not None:
            x = post(x)
    return x


def splice(new, x0, loud, loud0, t0, t1, **fit_kw):
    """New head, original tail: `new` up to t0 (s), raised-cosine crossfade to the
    original render `x0` by t1, with x0 scaled so that after finish() normalises
    the result to `loud` its tail sits at exactly the absolute level the original
    had when normalised to `loud0` (both renders start with the same take() shot,
    so the crossfade is between coherent signals). Returns the fit() result."""
    n = max(len(new), len(x0))
    new, x0 = pad_to(new, n), pad_to(x0, n)
    u = np.clip((times(n) - t0) / (t1 - t0), 0, 1)
    h = 0.5 + 0.5 * np.cos(np.pi * u)                    # 1 = new head, 0 = original tail
    g0 = loud0 - loudness_db(highpass(x0, 35, 2))         # finish()'s gain on the original (dB)
    k = 0.0                                               # tail gain (dB) on x0 inside the mix
    for _ in range(20):
        y = fit(h * new + (1 - h) * db(k) * x0, loud, **fit_kw)
        g1 = loud - loudness_db(highpass(y, 35, 2))
        if abs(g0 - g1 - k) < 1e-4:
            break
        k = g0 - g1
    return y


# --------------------------------------------------------------------------
# gun-handling foley kit: real Model 12 pump / Marlin 336 lever strokes from
# the Free Firearm Sound Library (cut, high-passed, gated), plus synthesized
# parts: one fixed noise-modal body per gun part (B.noise_ir, the same in
# every variant) struck with B.modal_hit / rubbed with B.scrape
# --------------------------------------------------------------------------
def _fixed_rng(tag):
    """Deterministic generator for things that must be identical in every
    variant (a gun's body resonances)."""
    return np.random.default_rng(zlib.crc32(("gun_foley:" + tag).encode()))


def _movmax(x, w):
    if w <= 1:
        return x
    xp = np.pad(x, (w // 2, w - w // 2 - 1), mode="edge")
    return np.lib.stride_tricks.sliding_window_view(xp, w).max(axis=1)


def _gate(x, thr_db=-36.0, ratio=3.0, win=0.0015, hold=0.004, smooth=0.003):
    """Look-ahead downward expander (relative to the clip peak): keeps the
    clicks, pushes the field recording's background down between them."""
    pk = np.max(np.abs(x)) + 1e-12
    w = max(1, n_of(win))
    env = np.sqrt(np.convolve(x * x, np.ones(w) / w, mode="same")) / pk + 1e-9
    gdb = np.clip((20 * np.log10(env) - thr_db) * (ratio - 1.0), -60.0, 0.0)
    gdb = _movmax(gdb, n_of(hold))
    s = max(1, n_of(smooth))
    gdb = np.convolve(gdb, np.ones(s) / s, mode="same")
    return x * 10 ** (gdb / 20)


def _rec(c, rel, t0, t1, hp=300.0, thr_db=-36.0, ratio=3.0):
    """Slice of a Free Firearm Sound Library take, cleaned for use as foley."""
    x = c.o(FF, FFP + rel)
    seg = highpass(x[n_of(t0): n_of(t1)].copy(), hp, 4)
    seg = _gate(seg, thr_db, ratio)
    return B.unit(fade(seg, 0.002, 0.012))


def _gun_ir(tag, octs, peaks=()):
    """A gun part's fixed noise-modal body (B.noise_ir), identical in every variant."""
    return B.noise_ir(_fixed_rng(tag), octs, peaks)


def _thock(rng, f0, f1, tau, dur=0.08, noise_db=-5.0, nz_fc=2200.0):
    """Short low-mid body knock: the weight behind a clack (receiver / stock /
    palm). Kept short and above ~150 Hz so it punches instead of booming."""
    th = B.thump(f0, f1, 0.005, tau, dur, partial2=0.25)
    nz = B.lp_burst(rng, dur, nz_fc, tau * 0.35, attack=0.0003)
    return B.unit(highpass(th + db(noise_db) * nz, 120, 2))


def _nbody(rng, fc=450.0, q=1.2, tau=0.008, dur=0.05, hp=150.0):
    """Unpitched low-mid body knock: band-passed decaying noise (no sine glide,
    so it adds weight without a kick-drum 'tok' undertone)."""
    return B.unit(highpass(B.burst(rng, dur, fc, q, tau, attack=0.0003), hp, 2))


def _lowmid_lump_db(x, t, dur=0.04, n=8192):
    """How far the strongest 100-700 Hz bin of a 40 ms window stands above the
    band's median (a boxy mode / pitched 'tok' shows up as a big number)."""
    seg = x[n_of(t): n_of(t) + n_of(dur)]
    sp = np.abs(np.fft.rfft(seg * np.hanning(len(seg)), n)) ** 2
    f = np.fft.rfftfreq(n, 1 / SR)
    sel = (f >= 100) & (f < 700)
    return 10 * np.log10(np.max(sp[sel]) / (np.median(sp[sel]) + 1e-30) + 1e-30)


def _fit_body(tag, layers, idx, t_ev, fc=280.0, q=0.6, tau=0.009, hp=100.0, tries=10):
    """Unpitched body knock that sits evenly under the rest of the hit. A short
    noise burst's spectrum has random lumps, and where one coincides with the
    real stroke's own low-mid resonance they build a boxy 'mode' 10+ dB up. So
    of several takes (fixed seed per tag: deterministic, the same every build)
    keep the one whose low-mids in the actual mix stay flattest in 40 ms
    windows around the event -- a foley editor picking the take that fits.
    layers: the _mixs layer list; layers[idx] is the body slot (its offset and
    gain are used). Returns the chosen body signal."""
    r = _fixed_rng("body:" + tag)
    lead = -min(0.0, min(off for _, off, _ in layers))
    best, score = None, np.inf
    for _ in range(tries):
        b = _nbody(r, fc, q, tau, 0.05, hp)
        trial = [(s, o + lead, g) for s, o, g in layers]
        trial[idx] = (b, trial[idx][1], trial[idx][2])
        x = mix(0.0, *trial)
        worst = max(_lowmid_lump_db(x, t_ev + lead + d)
                    for d in (-0.004, -0.002, 0.0, 0.002, 0.004, 0.006))
        if worst < score:
            best, score = b, worst
    return best


def _cloth(c, stem, start, dur, hp=250.0, speed=1.0):
    """Short Kenney cloth/leather rustle slice with soft edges."""
    x = c.k("rpg-audio", stem, start=start, dur=dur, speed=speed)
    return B.unit(fade(highpass(x, hp, 2), 0.01, 0.04))


def _mixs(length, *layers):
    """mix() that accepts negative offsets (a recorded stroke whose pre-roll
    starts before t=0): everything is shifted so the earliest layer is at 0."""
    lead = -min(0.0, min(off for _, off, _ in layers))
    return mix(length + lead, *[(s, off + lead, g) for s, off, g in layers])


def _trim_head(x, thresh_db=-50.0, pre=0.002):
    """Drop the near-silent lead-in (gated recording pre-roll) so the sound
    starts the moment the game triggers it; build_audio fades the first 1.5 ms."""
    a = np.abs(x)
    i = int(np.argmax(a > np.max(a) * db(thresh_db)))
    return x[max(0, i - n_of(pre)):]


def _room(x, rng, mix_db=-21.0, decay=0.2):
    """A touch of near space so the layers glue (foley is held at arm's length)."""
    return reverb(x, rng, decay=decay, mix_db=mix_db, predelay=0.004, bright=7000.0, tail=0.04)


# ---- fixed gun bodies (identical in every variant) ----
# Octave tables are (centre Hz, gain dB, decay tau s); peaks are (Hz, Q, dB, tau).
# Decays are matched to the real Model 12 / Marlin clacks in the Free Firearm
# Sound Library (t20 ~ 6-16 ms for a clack, longer only for the bolt's clinks).
def _ir_shotgun_receiver():
    # steel receiver + bolt: dense, mid-forward 'clack', short
    return _gun_ir("shotgun_receiver",
                   [(250, -16, 0.004), (500, -8, 0.005), (1000, -2, 0.007), (2000, 0, 0.008),
                    (4000, -3, 0.007), (8000, -9, 0.005), (16000, -18, 0.003)],
                   [(2380, 14, -4, 0.018), (3910, 16, -6, 0.014), (6120, 18, -9, 0.01)])


def _ir_shotgun_forend():
    # polymer forend on the magazine tube: dull, short, mid-heavy
    return _gun_ir("shotgun_forend",
                   [(250, -8, 0.004), (500, -2, 0.005), (1000, 0, 0.005), (2000, -5, 0.004),
                    (4000, -12, 0.003), (8000, -20, 0.002)],
                   [(820, 6, -5, 0.008), (1450, 7, -7, 0.006)])


def _ir_bolt_steel():
    # bolt-action receiver: hard and bright, with rough 'clink' rings
    return _gun_ir("sniper_bolt",
                   [(250, -26, 0.003), (500, -18, 0.004), (1000, -9, 0.006), (2000, -3, 0.008),
                    (4000, 0, 0.009), (8000, -2, 0.008), (16000, -8, 0.005)],
                   [(3170, 30, -1, 0.045), (4630, 30, -2, 0.038), (6890, 35, -3, 0.03),
                    (9420, 35, -6, 0.02)])


def _ir_rifle_steel():
    # generic carbine: magazine catch, bolt carrier, charging handle
    return _gun_ir("rifle_steel",
                   [(250, -20, 0.004), (500, -11, 0.005), (1000, -4, 0.007), (2000, 0, 0.009),
                    (4000, -1, 0.008), (8000, -6, 0.006), (16000, -14, 0.004)],
                   [(2860, 18, -4, 0.022), (4410, 20, -5, 0.018), (7150, 24, -8, 0.013)])


def _ir_mag_polymer():
    # polymer magazine body
    return _gun_ir("mag_polymer",
                   [(250, -6, 0.004), (500, 0, 0.005), (1000, -1, 0.005), (2000, -6, 0.004),
                    (4000, -13, 0.003), (8000, -22, 0.002)],
                   [(910, 6, -3, 0.008), (1580, 7, -5, 0.006)])


def _ir_small_steel():
    # sling swivels, safety lever, small pins: tiny bright parts
    return _gun_ir("small_steel",
                   [(1000, -16, 0.0025), (2000, -7, 0.0035), (4000, 0, 0.0045), (8000, -1, 0.004),
                    (16000, -9, 0.003)],
                   [(4870, 22, -4, 0.012), (7330, 24, -6, 0.01), (10210, 26, -9, 0.008)])


# --------------------------------------------------------------------------
# weapon recipes
# --------------------------------------------------------------------------
@recipe("pistol_fire", variants=3, loud=-8.5)
def pistol_fire(c, v):
    """9 mm pistol, all variants from the owner's favourite take (X_39P take 3):
    hard snappy crack + tight low-mid thump, slide clack, short outdoor tail."""
    r = c.rng
    sp = [0.975, 1.022, 1.0][v]                          # small natural variation
    shot = take(c.o(FF, FFP + "Walther PPQ/X_39P.wav"), 10.68, 0.8, hold=0.06, tau=0.16)   # take 3
    shot = peak_eq(varispeed(shot, sp), 3500, 2.5, q=0.8)
    crk = B.snap(r, [3300, 3700, 3500][v], 0.9, 0.003)
    # the same gun's mid-distance take for body; flipped, its crack lines up with (not
    # against) the near take's crack in the first 3 ms
    room = take(c.o(FF, FFP + "Walther PPQ/X_31P.wav"), [1.085, 5.243, 1.085][v], 0.5, hold=0.05, tau=0.12)
    room = -varispeed(highpass(room, 120), sp)
    thump = B.kick([168, 180, 172][v], 90, 0.007, 0.014, 0.1, drive=1.6)
    bod = B.lowbody(r, 0.12, 90, 500, 0.018)
    slide = highpass(c.k("rpg-audio", "metalLatch", speed=1.35), 1500)
    crunch = highpass(c.k("impact-sounds", f"impactWood_light_00{v}", speed=1.4), 400)
    thump = agree(shot, thump, PRE)
    x = mix(0.7, (shot, 0, 0), (room, 0.0005, -6), (crk, PRE, -7), (thump, PRE, -3), (bod, PRE, -7))
    x = saturate(x / np.max(np.abs(x)), 1.3)
    # short, dense head: 300 Hz-6 kHz body raised for ~12 ms (no 6-16 kHz fizz)
    x = head_bus(x, PRE, boost_db=8, hp=300, lp=6000, hold=0.012, fade=0.02, drive=1.6, smash_db=-5, thr=-30,
                 ratio=4)
    x = mix(0.7, (x, 0, 0), (slide, PRE + [0.033, 0.037, 0.035][v], -19), (crunch, PRE + 0.004, -22))
    x = reverb(x, r, decay=0.55, mix_db=-17, tail=0.05)
    return fit(x, -8.5, margin=CLIP_MARGIN, gate=(0.0008, 0.0002), clip=4.0)


@recipe("shotgun_fire", variants=3, loud=-7.0)
def shotgun_fire(c, v):
    """Regular 12-gauge pump: near take for the blast + a mid-distance take of the
    same gun for the real outdoor slap-backs, a big audible low-mid boom body,
    tight thump + crack at the front, a short head sub, rolling tail."""
    r = c.rng
    near_p, near_t, mid_p, mid_t = [
        ("Nova/O_21P.wav", 0.43, "Nova/O_17P.wav", 0.694),
        ("Nova/O_21P.wav", 3.47, "Nova/O_17P.wav", 3.708),
        ("Model 12/K_22P.wav", 0.84, "Model 12/K_17P.wav", 0.907)][v]
    near = take(c.o(FF, FFP + near_p), near_t, 0.9, hold=0.15, tau=0.3)
    mid = take(c.o(FF, FFP + mid_p), mid_t, 2.3, hold=0.5, tau=0.7)
    deep = lowpass(varispeed(near[: n_of(0.5)], 0.62), 800, 2)   # the blast an octave-ish down
    deep = deep[n_of(PRE / 0.62 - PRE):]                         # its onset back on the real one
    deep = pregate(deep, PRE, 0.0003, 0.0)                       # no low-pass pre-ringing ahead of it
    thump = B.kick([90, 110, 90][v], 50, 0.016, 0.085, 0.6, drive=1.8)
    sub = B.thump(66, 42, 0.04, 0.12, 0.6)                      # deep weight underneath
    hsub = B.thump(70, 45, 0.03, 0.03, 0.3)                     # short head sub, after the saturation
    boom = B.lowbody(r, 1.0, 55, 520, 0.13, attack=0.002)
    crk = B.snap(r, 3000, 0.8, 0.0028)
    pellets = highpass(c.k("impact-sounds", f"impactWood_light_00{(v + 3) % 5}", speed=1.2), 400)
    thump = agree(near, thump, PRE)
    sub = agree(near, sub, PRE)
    deep = agree(near, deep, 0.0)
    x = mix(2.0, (near, 0, 0), (mid, 0.001, -4), (deep, 0, -7), (thump, PRE, -5), (sub, PRE, -11),
            (boom, PRE, -7), (crk, PRE, -11))
    x = saturate(x / np.max(np.abs(x)), 1.5)
    x = head_bus(x, PRE, boost_db=4, hp=150, hold=0.08, fade=0.1, drive=1.7, smash_db=-6, thr=-30, ratio=3)
    hsub = agree(x, hsub, PRE, lp=80, win=0.012)
    x = mix(2.0, (x, 0, 0), (pellets, PRE + 0.005, -22), (hsub, PRE, [-4.5, -9, -9][v]))
    x = _rolling_echoes(x, r, [(0.23, -16, 1800), (0.55, -20, 1200), (0.95, -25, 850)])
    x = reverb(x, r, decay=1.7, mix_db=-14, tail=0.1)[: n_of(2.4)]
    return fit(x, -7.0, margin=CLIP_MARGIN, clip=2.0)


@recipe("shotgun_pump", variants=2, loud=-13.0, src="mixed")
def shotgun_pump(c, v):
    """Pump-action rack: forend slides back (bolt unlocks, shell kicks out, hits
    the rear stop: 'shuck'), then slams forward and locks into battery ('SHUCK')."""
    r = c.rng
    rec_ir = _ir_shotgun_receiver()
    fe_ir = _ir_shotgun_forend()
    # real strokes: back slice + its clack time, forward slice + its clack time.
    # hp 160: the real strokes keep whatever body they have (they carry almost
    # nothing below 300 Hz at the click anyway; the gate removes the wind).
    if v == 0:
        back = _rec(c, "Model 12/K_22P.wav", 4.205, 4.372, hp=160)
        fwd = _rec(c, "Model 12/K_22P.wav", 4.700, 4.885, hp=160)
        b_clk, f_clk = 4.282 - 4.205, 4.834 - 4.700
        tb, tf = 0.075, 0.235
        rec_db, back_db = 0, -5.5
    else:
        back = _rec(c, "Model 12/K_17P.wav", 3.075, 3.215, hp=160, thr_db=-24, ratio=4)
        fwd = _rec(c, "Model 12/K_17P.wav", 3.955, 4.04, hp=160, thr_db=-24, ratio=4)
        b_clk, f_clk = 3.160 - 3.075, 4.002 - 3.955
        tb, tf = 0.07, 0.215
        rec_db, back_db = -1, -4

    # back stroke: polymer-on-tube slide, then the bolt hits the rear stop
    slide_b = B.scrape(r, 0.065, 900, 6500, ir=fe_ir, grains=420, rough=0.8,
                       shape=((0, 0), (0.5, 1), (0.95, 0.7), (1, 0)))
    # (synthetic hits are high-passed: the real stroke + one even noise body
    # own the low-mids, so no boxy synthetic mode sits under the rack)
    clack_b = highpass(B.modal_hit(r, rec_ir, hard=0.0002, rebounds=((0.006, -8), (0.017, -14), (0.03, -20))), 550, 2)
    knock_b = highpass(B.modal_hit(r, fe_ir, hard=0.0005, rebounds=((0.004, -10),), tick_db=-14, tick_fc=2000), 550, 2)
    shk_b = B.shk(r, 0.03, 2500, 12000, 0.009)
    shell = B.unit(highpass(c.k("impact-sounds", f"impactWood_light_00{(v + 1) % 5}", speed=1.7), 900))

    # forward stroke: faster slide, then the bolt locks into battery (the big one)
    slide_f = B.scrape(r, 0.06, 1100, 7000, ir=rec_ir, grains=500, rough=0.8,
                       shape=((0, 0), (0.4, 0.8), (0.9, 1), (1, 0)))
    clack_f = highpass(B.modal_hit(r, rec_ir, hard=0.00016, rebounds=((0.005, -6), (0.012, -11), (0.024, -21))), 550, 2)
    knock_f = highpass(B.modal_hit(r, fe_ir, hard=0.0004, rebounds=((0.003, -9),), tick_db=-12, tick_fc=2200), 550, 2)
    shk_f = B.shk(r, 0.03, 2500, 12000, 0.008)

    layers = [(back, tb - b_clk, rec_db + back_db),  # back stroke ~2-4 dB under the lock
              (slide_b, tb - 0.062, -17),
              (clack_b, tb, -14),
              (knock_b, tb + 0.001, -16),
              (np.zeros(1), tb, -12),  # 4: back-stroke body (fitted below)
              (shk_b, tb, -15),
              (shell, tb + 0.06 + 0.01 * v, -24),
              (fwd, tf - f_clk, rec_db + 3),
              (slide_f, tf - 0.058, -14),
              (clack_f, tf, -6),
              (knock_f, tf + 0.001, -15),
              (np.zeros(1), tf, -7),  # 11: forward-stroke body (fitted below)
              (shk_f, tf, -8)]
    layers[4] = (_fit_body(f"pump_back_{v}", layers, 4, tb, 280, 0.6, 0.007, hp=110),) + layers[4][1:]
    layers[11] = (_fit_body(f"pump_fwd_{v}", layers, 11, tf, 300, 0.6, 0.009, hp=110),) + layers[11][1:]
    x = _mixs(0.5, *layers)
    x = peak_eq(x, 3200, 2.0, q=0.9)  # presence: the "shk" of the rack
    x = saturate(x, 1.8)
    return _trim_head(_room(x, r, mix_db=-22))


@recipe("lmg_fire", variants=4, loud=-11.0)
def lmg_fire(c, v):
    """LMG (7.62): the same chunky AK core, belt rattle and short tail as before,
    a bit deeper overall: slower varispeed, lower/heavier (polarity-matched) body
    thump, more low-end EQ and a touch less fizz; mechanics a few % lower."""
    r = c.rng
    rec = c.o(FF, FFP + "AK-47/C_28P.wav")  # near perspective, 4 single takes
    shot = take(rec, [0.61, 3.26, 6.03, 9.175][v], 0.5, hold=0.05, tau=0.09)
    shot = varispeed(shot, [0.92, 0.90, 0.93, 0.91][v])        # was 0.93-0.96
    shot = peak_eq(shot, 115, 5.0, q=0.9)                        # was +4 dB @ 130 Hz
    shot = shelf(shot, 5000, -1.5)                               # a touch less fizz
    crk = B.crack(r, 0.0025, 3200)
    body = B.thump(78, 46, 0.02, 0.045, 0.22)                   # was 85 -> 50 Hz
    links = highpass(c.k("rpg-audio", "beltHandle1", speed=1.15), 1500)
    latch = highpass(c.k("rpg-audio", "metalLatch", dur=0.12, speed=1.05), 1100)
    crunch = highpass(c.k("impact-sounds", f"impactWood_light_00{v % 5}", speed=1.2), 350)
    body = agree(shot, body, PRE)
    x = mix(0.5, (shot, 0, 0), (crk, PRE, -11.5), (body, PRE, -9), (links, PRE + 0.05, -25),
            (latch, PRE + 0.04, -23), (crunch, PRE + 0.004, -22))
    x = saturate(x, 1.5)
    x = reverb(x, r, decay=0.38, mix_db=-21, tail=0.03)[: n_of(0.52)]
    return fit(x, -11.0)


@recipe("smg_fire", variants=4, loud=-11.0)
def smg_fire(c, v):
    """9 mm SMG (Carl Gustav M45): very fast punchy attack, tight body, short tail
    so 900 rpm bursts (one shot per ~67 ms) stay crisp but read as gunfire."""
    r = c.rng
    path, t, sp, dur = [("Carl Gustav M45/G_31P.wav", 0.31, 1.0, 0.25),
                        ("Carl Gustav M45/G_33P.wav", 4.358, 1.02, 0.088),   # mid-burst shot
                        ("Carl Gustav M45/G_31P.wav", 3.501, 0.985, 0.25),
                        ("Carl Gustav M45/G_33P.wav", 0.394, 1.01, 0.088)][v]
    shot = varispeed(take(c.o(FF, FFP + path), t, dur, hold=0.03, tau=0.05), sp)
    crk = B.snap(r, 3800, 0.9, 0.0015)
    thump = B.kick([215, 222, 210, 218][v], 110, 0.005, 0.01, 0.07, drive=1.4)
    bod = B.lowbody(r, 0.09, 110, 600, 0.012)
    crunch = highpass(c.k("impact-sounds", f"impactWood_light_00{(v + 1) % 5}", speed=1.7), 500)
    thump = agree(shot, thump, PRE)
    x = mix(0.25, (shot, 0, 0), (crk, PRE, -9), (thump, PRE, -13), (bod, PRE, -13))
    x = saturate(x / np.max(np.abs(x)), 1.3)
    x = head_bus(x, PRE, boost_db=5, hp=300, hold=0.015, fade=0.025, drive=1.5)
    x = mix(0.25, (x, 0, 0), (crunch, PRE + 0.003, -24))
    x = reverb(x, r, decay=0.3, mix_db=-19, tail=0.02)
    return fit(x, -11.0)


_RIFLE_BASE_LOUD = -10.0  # the level rifle_fire's slap-back + tail were approved at


def _rifle_fire_base(c, v):
    """The original 5.56 render (crack + body thump, slap-back, medium outdoor
    tail); not a recipe of its own: rifle_fire keeps its tail from ~65 ms on."""
    r = c.rng
    # two near-perspective AR-15 takes; the third variant re-uses take 1 a few % brighter
    t, sp = [(0.705, 1.0), (5.66, 1.0), (0.705, 1.035)][v]
    shot = varispeed(take(c.o(FF, FFP + "AR-15/D_32P.wav"), t, 1.2, hold=0.14, tau=0.4), sp)
    crk = B.crack(r, 0.0025, 3500)
    body = B.thump(95, 55, 0.025, 0.05, 0.3)
    bolt = highpass(c.k("rpg-audio", "metalClick", start=0.085, dur=0.07, speed=1.2), 1200)
    crunch = highpass(c.k("impact-sounds", f"impactWood_light_00{(v + 2) % 5}", speed=1.3), 400)
    x = mix(1.1, (shot, 0, 0), (crk, PRE, [-9, -9, -8][v]), (body, PRE, [-11, -11, -12][v]),
            (bolt, PRE + 0.03, -21), (crunch, PRE + 0.004, -22))
    x = saturate(x, 1.4)
    x = _rolling_echoes(x, r, [(0.17, -20, 2200)])
    return reverb(x, r, decay=1.0, mix_db=-15, tail=0.1)


@recipe("rifle_fire", variants=3, loud=-8.5)
def rifle_fire(c, v):
    """Assault rifle (5.56): the punch goes into the first ~10 ms (tight thump,
    lifted crack, dense 150 Hz-2.5 kHz body that never out-peaks the crack's
    moment), then the original render's slap-back and tail at exactly their
    original level ('otherwise good')."""
    x0 = _rifle_fire_base(c, v)          # the original render: its slap-back / tail are kept
    r = c.rng
    t, sp = [(0.705, 1.0), (5.66, 1.0), (0.705, 1.035)][v]
    shot = varispeed(take(c.o(FF, FFP + "AR-15/D_32P.wav"), t, 1.2, hold=0.14, tau=0.4), sp)
    crk = B.snap(r, 3400, 0.9, 0.002)
    thump = B.kick([135, 135, 140][v], 64, 0.009, 0.012, 0.2, drive=1.6)
    sub = B.thump(70, 48, 0.03, 0.07, 0.45)              # a little of the old low weight
    bod = B.lowbody(r, 0.18, 80, 500, 0.03)
    bolt = highpass(c.k("rpg-audio", "metalClick", start=0.085, dur=0.07, speed=1.2), 1200)
    crunch = highpass(c.k("impact-sounds", f"impactWood_light_00{(v + 2) % 5}", speed=1.3), 400)
    thump = agree(shot, thump, PRE)
    sub = agree(shot, sub, PRE, lp=120)
    x = mix(1.1, (shot, 0, 0), (crk, PRE, [-9, -9, -8][v]), (thump, PRE, [-4, -2, -4][v]), (sub, PRE, -18),
            (bod, PRE, [-12, -13, -10][v]))
    x = saturate(x / np.max(np.abs(x)), 1.4)
    x = head_bus(x, PRE, boost_db=[6, 6, 8][v], hp=150, lp=2500, hold=0.005, fade=0.01, drive=1.5, smash_db=-5,
                 thr=-30, ratio=4)
    x = crack_lift(x, PRE, [3, 3, 4][v], fc=2000.0, until=0.0025, fade=0.0015, lead=0.0002)
    x = mix(1.1, (x, 0, 0), (bolt, PRE + 0.03, -21), (crunch, PRE + 0.004, -22))
    x = reverb(x, r, decay=1.0, mix_db=-15, tail=0.1)
    x = head_sub_fix(x, end=0.03, fc=12.0)
    return splice(x, x0, -8.5, _RIFLE_BASE_LOUD, 0.035, 0.065, margin=CLIP_MARGIN, gate=(0.0008, 0.0002),
                  clip=8.0, post=hit_clamp(x0, -0.8))


_SNIPER_BASE_LOUD = -8.0  # the level sniper_fire's echo / trail-off were approved at


def _sniper_fire_base(c, v):
    """The original .30-06 render (huge crack, deep boom, long rolling echo); not a
    recipe of its own: sniper_fire keeps it from ~60 ms on."""
    r = c.rng
    near = take(c.o(FF, FFP + "Tikka/W_29P.wav"), [0.575, 5.675][v], 2.9, hold=0.35, tau=0.9)
    far = take(c.o(FF, FFP + "Tikka/W_24P.wav"), [0.755, 5.385][v], 2.9, hold=0.5, tau=1.0)
    snap = B.crack(r, 0.0015, 5000)            # supersonic snap on top
    hiss = B.burst(r, 0.1, 7000, 0.7, 0.01)
    deep = B.thump(80, 46, 0.05, 0.22, 1.2)    # deep boom (kept above ~40 Hz so it reads on speakers)
    rumble = B.lp_burst(r, 2.6, 200, 0.7, attack=0.06)
    crunch = highpass(c.k("impact-sounds", f"impactWood_light_00{v + 1}", speed=1.1), 400)
    x = mix(2.9, (near, 0, 0), (lowpass(far, 3000, 1), 0.012, -9), (snap, PRE, -7), (hiss, PRE, -15),
            (deep, PRE, -6), (rumble, 0.03, -17), (crunch, PRE + 0.004, -23))
    x = saturate(highpass(x, 40, 2), 1.5)
    x = _rolling_echoes(x, r, [(0.32, -15, 2200), (0.71, -19, 1400), (1.15, -24, 900), (1.7, -29, 650)])
    return reverb(x, r, decay=1.6, mix_db=-16, tail=0.0)[: n_of(3.0)]


@recipe("sniper_fire", variants=2, loud=-6.5)
def sniper_fire(c, v):
    """.30-06 bolt rifle: a deeper, heavier punch at the shot onset (aligned
    pitched-down copy of the shot, fast deep thump, low noise body, dense short
    head that never out-peaks the original's hit time), then the original render
    (crack, boom, long rolling echo) at exactly its original absolute level from
    60 ms on."""
    x0 = _sniper_fire_base(c, v)        # same rng draws -> identical echo / trail-off
    r = c.rng
    near = take(c.o(FF, FFP + "Tikka/W_29P.wav"), [0.575, 5.675][v], 0.2, hold=0.04, tau=0.04)
    heavy = lowpass(varispeed(near, 0.55), 700, 2)          # the shot itself, much deeper
    heavy = heavy[n_of(PRE / 0.55 - PRE):]                  # its onset back on the real one
    heavy = pregate(heavy, PRE, 0.0003, 0.0)                # no low-pass pre-ringing ahead of the shot
    thump = B.kick(130, 50, 0.01, 0.02, 0.3, attack=0.0004, drive=2.0)
    bod = B.lowbody(r, 0.25, 45, 260, 0.035, attack=0.001)
    x0n = crack_lift(x0 / np.max(np.abs(x0)), PRE, [1.0, -1.0][v])   # crack level held vs the heavier hit
    heavy = agree(x0n, heavy, 0.0)
    thump = agree(x0n, thump, PRE)
    p = mix(len(x0) / SR, (heavy, 0, -10), (thump, PRE, 0.5), (bod, PRE, -10))
    x = x0n + pad_to(p, len(x0n))
    x = head_bus(x, PRE, boost_db=3, hp=None, hold=0.015, fade=0.02, drive=1.6, smash_db=-8, thr=-30, ratio=3,
                 sat_until=0.04)
    x = head_sub_fix(x, end=0.06, fc=40.0)
    # punchy head until 25 ms, crossfaded by 60 ms into the original render at its exact level
    return splice(x, x0, -6.5, _SNIPER_BASE_LOUD, 0.025, 0.06, margin=CLIP_MARGIN, clip=4.0,
                  post=hit_clamp(x0, -0.8, margin5_db=0.0))


@recipe("sniper_bolt", loud=-13.5, src="mixed")
def sniper_bolt(c, v):
    """Bolt cycle with bright, hard steel clinks (lift - back - forward - lock)
    and a faint tick of the spent carrot stub."""
    r = c.rng
    ir = _ir_bolt_steel()
    lever = [_rec(c, "Marlin 336/I_22P.wav", t, t + 0.05, hp=600, thr_db=-22, ratio=4)
             for t in (4.349, 4.766, 5.374)]
    T_LIFT, T_BACK, T_FWD, T_LOCK = 0.004, 0.209, 0.434, 0.579

    # 1. lift: cocking-piece cam clicks over (click + tiny cam scrape)
    lift = B.modal_hit(r, ir, hard=0.00012, rebounds=((0.004, -9),), tick_db=-4, tick_fc=4500)
    cam = B.scrape(r, 0.035, 2500, 9000, ir=ir, grains=600, shape=((0, 0), (0.3, 1), (1, 0)))
    # 2. pull back: steel slides on the rails, hits the bolt stop (CLINK)
    rail_b = B.scrape(r, 0.13, 2000, 10000, ir=ir, grains=520, rough=0.85,
                      shape=((0, 0), (0.15, 0.7), (0.85, 1), (1, 0)))
    stop = B.modal_hit(r, ir, hard=0.0001, rebounds=((0.006, -6), (0.016, -12)), tick_db=-3, tick_fc=5000)
    stub = B.unit(highpass(c.k("impact-sounds", "impactWood_light_002", speed=1.9), 1200))
    # 3. push forward: rails again, the round is picked up and the bolt seats
    rail_f = B.scrape(r, 0.1, 1800, 9000, ir=ir, grains=480, rough=0.85,
                      shape=((0, 0), (0.2, 1), (0.9, 0.8), (1, 0)))
    seat = B.modal_hit(r, ir, hard=0.00012, rebounds=((0.005, -7), (0.011, -12)), tick_db=-4)
    seat_body = _thock(r, 420, 240, 0.009)
    # 4. lock down: handle drops into its notch -- the hardest clink
    lock = B.modal_hit(r, ir, hard=0.00008, rebounds=((0.004, -5), (0.011, -11), (0.022, -17)),
                       tick_db=-2, tick_fc=5500)
    lock_body = _thock(r, 380, 220, 0.01)

    x = _mixs(0.8,
              (lift, T_LIFT, -4), (cam, T_LIFT + 0.004, -20), (lever[0], T_LIFT, -8),
              (rail_b, T_BACK - 0.13, -19), (stop, T_BACK, -1), (lever[1], T_BACK, -7),
              (stub, T_BACK + 0.07, -20),
              (rail_f, T_FWD - 0.1, -20), (seat, T_FWD, -3), (seat_body, T_FWD, -17),
              (lock, T_LOCK, 0), (lock_body, T_LOCK, -15), (lever[2], T_LOCK, -7))
    x = peak_eq(x, 5500, 2.5, q=0.8)  # extra 'clink' sparkle
    x = saturate(x, 1.2)
    return _trim_head(_room(x, r, mix_db=-21))


@recipe("scope_in", loud=-20.0, src="synth")
def scope_in(c, v):
    """Soft lens/zoom 'zip' when aiming down the sniper scope."""
    r = c.rng
    zip_ = B.whoosh(r, 0.2, 1400, 5200, q=2.0, peak=0.7, slope=-1.0)
    n = n_of(0.2)
    glide_ = sine(np.geomspace(900, 1500, n), n) * env_pts(n, [(0, 0), (0.12, 1), (0.2, 0)])
    click = B.crack(r, 0.0015, 3000)
    return mix(0.3, (zip_, 0, 0), (glide_, 0, -18), (click, 0.19, -12))


@recipe("rocket_fire", variants=2, loud=-9.0)
def rocket_fire(c, v):
    """Launcher: deep whoosh-thump back-blast, rocket motor roaring away, sizzle."""
    r = c.rng
    rec = c.o(FF, FFP + "Mossberg/N_30P.wav")  # 12-ga blast, slowed into a deep launch thump
    blast = varispeed(take(rec, [1.7, 4.97][v], 1.6, hold=0.12, tau=0.3), [0.7, 0.66][v])
    motor = c.o("baradari-launches", "launches/rlaunch.wav")
    motor = varispeed(motor, [1.0, 0.92][v])
    motor = motor * env_pts(len(motor), [(0, 1), (0.6, 0.8), (len(motor) / SR, 0)])
    thump = B.thump(85, 42, 0.05, 0.14, 0.9)
    whoosh = B.whoosh(r, 1.3, 350, 2400, q=1.1, peak=0.18, slope=-1.5)
    sizzle = B.crackle(r, 1.4, 110, 1500, 7000)
    sizzle = sizzle * env_pts(len(sizzle), [(0, 0.3), (0.1, 1), (1.4, 0)])
    x = mix(2.0, (blast, 0, 0), (motor, PRE + 0.01, -5), (thump, PRE, -6), (whoosh, PRE, -9),
            (sizzle, PRE + 0.03, -13))
    x = saturate(x, 1.4)
    return reverb(x, r, decay=1.0, mix_db=-15, tail=0.1)[: n_of(2.4)]


@recipe("rocket_whoosh_loop", loud=-16.0, loop=True)
def rocket_whoosh_loop(c, v):
    r = c.rng
    L, X = 2.5, 0.3
    tot = L + X
    n = n_of(tot)

    def g(t, f):  # 6 Hz spiral wobble -> 15 whole cycles per 2.5 s loop
        fc = 1100 * (1 + 0.18 * np.sin(2 * np.pi * 6 * t))
        return bp_gain(f, fc, 0.9) + 0.25 * bp_gain(f, 4500, 0.6)

    roar = B.unit(stft_filter(colored(n, r, -1.5), g))
    roar *= 1 + 0.12 * np.sin(2 * np.pi * 6 * times(n))
    sputter = B.crackle(r, tot, 30, 1000, 4000)
    thr = c.k("sci-fi-sounds", "thrusterFire_001", start=1.5, dur=tot)
    x = mix(tot, (roar, 0, 0), (sputter, 0, -14), (pad_to(thr, n), 0, -5))
    return make_loop(x, L, X)


@recipe("explosion", variants=3, loud=-7.5)
def explosion(c, v):
    """Full-size Baradari blast at three speeds, each take with its own
    crunch / debris-clump choices, over synth boom, kick, poof and debris."""
    r = c.rng
    body = varispeed(c.o("baradari-explosions", "explosions/explode.wav"), [1.0, 0.95, 0.9][v])
    crunch = c.k("sci-fi-sounds", f"explosionCrunch_00{[0, 3, 3][v]}", speed=[1.0, 1.05, 1.0][v])
    sub = lowpass(c.k("sci-fi-sounds", "lowFrequency_explosion_001"), 300)
    boom = B.lp_burst(r, 2.0, 200, 0.35, attack=0.004)
    kick = B.thump(85, 45, 0.08, 0.2, 1.0)
    poof = B.burst(r, 0.8, 600, 0.7, 0.15, attack=0.003)
    debris = B.grains(r, 2.0, 30, 300, 3000, glen=(0.01, 0.03), t_tau=0.35, start=0.12)
    clump1 = c.k("impact-sounds", f"footstep_grass_00{v}", speed=0.9)
    clump2 = c.k("impact-sounds", f"impactSoft_medium_00{[1, 4, 3][v]}", speed=1.1)
    x = mix(2.2, (body, 0, 0), (crunch, 0, -5), (highpass(sub, 40), 0, -4), (boom, 0, -7), (kick, 0, -5),
            (poof, 0, -9), (debris, 0, -9), (clump1, [0.55, 0.62, 0.75][v], -13), (clump2, 0.8, -15))
    x = saturate(highpass(x, 40, 2), 1.7)
    return reverb(x, r, decay=1.3, mix_db=-12, tail=0.3)[: n_of(2.6)]


@recipe("reload_start", loud=-14.5, src="mixed")
def reload_start(c, v):
    """Mag-release button clicks, the magazine slides out and drops into the hand."""
    r = c.rng
    steel = _ir_rifle_steel()
    poly = _ir_mag_polymer()
    t_btn = 0.03
    t_out = t_btn + 0.085
    grip = _cloth(c, "handleSmallLeather", 0.0, 0.12, hp=400)
    # mag-release button: spring catch snaps (two-part click)
    btn = B.modal_hit(r, steel, hard=0.00012, rebounds=((0.003, -8),), tick_db=-4, tick_fc=4000)
    btn2 = B.modal_hit(r, steel, hard=0.00016, rebounds=(), tick_db=-6)
    # the mag drops free: a quick polymer "shk" down the well, rounds rattle
    slide = B.scrape(r, 0.06, 1500, 8000, ir=poly, grains=450, rough=0.85,
                     shape=((0, 0), (0.2, 1), (0.75, 0.6), (1, 0)))
    rattle = B.scrape(r, 0.05, 3000, 12000, ir=_ir_small_steel(), grains=200, rough=0.9,
                      ir_db=0, grain_count=4, shape=((0, 0), (0.1, 1), (1, 0)))
    clear = B.modal_hit(r, poly, hard=0.0004, rebounds=((0.006, -10),), tick_db=-10, tick_fc=2500)
    out_rec = _rec(c, "Model 12/K_22P.wav", 3.335, 3.40, hp=500)
    tok = B.unit(highpass(c.k("impact-sounds", "impactWood_light_003", speed=1.5), 600))
    # caught by the off hand
    catch = _cloth(c, "cloth4", 0.02, 0.12, hp=450)
    tap = B.modal_hit(r, poly, hard=0.0007, rebounds=(), tick_db=-20, tick_fc=1500)
    x = _mixs(0.4,
              (grip, 0, -20),
              (btn, t_btn, -1), (btn2, t_btn + 0.018, -7),
              (slide, t_btn + 0.022, -15), (rattle, t_btn + 0.03, -17),
              (clear, t_out, -4), (out_rec, t_out - 0.035, -6), (tok, t_out, -19),
              (catch, t_out + 0.06, -18), (tap, t_out + 0.1, -16))
    x = peak_eq(x, 3500, 2.0, q=0.8)
    x = saturate(x, 1.2)
    return _trim_head(_room(x, r, mix_db=-22))


@recipe("reload_end", loud=-13.0, src="mixed")
def reload_end(c, v):
    """Magazine seated firmly, then the bolt release slams the bolt home (the
    'ready' cue, the loudest event)."""
    r = c.rng
    steel = _ir_rifle_steel()
    poly = _ir_mag_polymer()
    # The game lets the critter fire on the same tick reload_end starts, so the
    # 'ready' cue must land fast: mag seats at 30 ms, the thumb hits the bolt
    # release and the bolt slams home at 115 ms (the loudest event), and the
    # whole thing is over by about 0.3 s.
    t_seat = 0.03
    t_slam = t_seat + 0.085
    # mag goes up the well and seats: polymer slap + catch snapping over
    ins = B.scrape(r, 0.035, 1000, 7000, ir=poly, grains=420, shape=((0, 0), (0.6, 1), (1, 0.6)))
    seat = B.modal_hit(r, poly, hard=0.00035, rebounds=((0.004, -8), (0.01, -14)), tick_db=-8, tick_fc=2500)
    catch = B.modal_hit(r, steel, hard=0.00012, rebounds=((0.003, -8),), tick_db=-4, tick_fc=4500)
    palm = _cloth(c, "dropLeather", 0.0, 0.08, hp=300)
    # bolt release lever pressed: a small click, the spring zips the bolt forward
    lever = B.modal_hit(r, _ir_small_steel(), hard=0.0001, rebounds=((0.003, -10),), tick_db=-5, tick_fc=5000)
    spring = B.scrape(r, 0.02, 2500, 11000, ir=steel, grains=900, rough=0.6,
                      shape=((0, 0), (0.3, 1), (1, 0.3)))
    # ... and the bolt slams into battery -- the big satisfying CLACK
    slam = B.modal_hit(r, steel, hard=0.0001, rebounds=((0.005, -6), (0.013, -11), (0.025, -18)),
                       tick_db=-2, tick_fc=4500)
    slam_rec = _rec(c, "Model 12/K_22P.wav", 4.828, 4.885)
    shk = B.shk(r, 0.03, 2500, 12000, 0.008)
    layers = [(ins, 0.0, -16), (palm, t_seat - 0.01, -20),
              (seat, t_seat, -9), (catch, t_seat + 0.004, -9),
              (np.zeros(1), t_seat, -12),  # 4: seat body (fitted below)
              (lever, t_slam - 0.024, -15),
              (spring, t_slam - 0.018, -17),
              (slam, t_slam, 0), (slam_rec, t_slam - 0.006, -5),
              (np.zeros(1), t_slam, -11),  # 9: slam body (fitted below)
              (shk, t_slam, -14)]
    layers[4] = (_fit_body("reload_end_seat", layers, 4, t_seat, 240, 0.6, 0.009, hp=90),) + layers[4][1:]
    layers[9] = (_fit_body("reload_end_slam", layers, 9, t_slam, 300, 0.6, 0.009, hp=110),) + layers[9][1:]
    x = _mixs(0.4, *layers)
    x = peak_eq(x, 3200, 1.5, q=0.8)
    x = saturate(x, 1.3)
    return _trim_head(_room(x, r, mix_db=-21))


@recipe("dry_fire", loud=-18.0)
def dry_fire(c, v):
    r = c.rng
    click = highpass(c.k("rpg-audio", "metalClick", start=0.05, dur=0.2, speed=1.25), 800)
    puff = B.burst(r, 0.08, 900, 0.8, 0.015, attack=0.002)
    return mix(0.25, (click, 0, 0), (puff, 0.004, -12))


@recipe("weapon_swap", variants=2, loud=-15.0, src="mixed")
def weapon_swap(c, v):
    """Quick draw: strap/cloth rustle, sling rattle, grip pat, ready click-clack."""
    r = c.rng
    small = _ir_small_steel()
    steel = _ir_rifle_steel()
    rustle = _cloth(c, ["cloth3", "cloth1"][v], [0.02, 0.06][v], 0.2, hp=300, speed=1.15)
    strap = _cloth(c, ["clothBelt", "clothBelt2"][v], [0.05, 0.1][v], 0.18, hp=400, speed=1.1)
    swish = B.whoosh(r, 0.16, 900, 3200, q=1.2, peak=0.55)
    # sling swivel / buckle rattle: a few small bright tinks
    tinks = []
    t = 0.07
    for k in range(4):
        h = B.modal_hit(r, small, hard=0.0001, rebounds=((0.003, -12),), tick_db=-8, tick_fc=5000)
        tinks.append((h, t, -12 - 3 * k + r.uniform(-2, 2)))
        t += r.uniform(0.018, 0.035)
    # weapon lands in the hands: grip pat + receiver knock
    grab = _thock(r, 280, 160, 0.01, noise_db=-2, nz_fc=1800)
    knock = B.modal_hit(r, steel, hard=0.0003, rebounds=((0.005, -12),), tick_db=-12, tick_fc=2500)
    # ready: safety lever 'click-clack'
    t_rdy = [0.255, 0.275][v]
    click1 = B.modal_hit(r, small, hard=0.00008, rebounds=((0.003, -9),), tick_db=-3, tick_fc=5000)
    click2 = B.modal_hit(r, steel, hard=0.00012, rebounds=((0.004, -10),), tick_db=-4, tick_fc=4500)
    x = _mixs(0.45,
              (rustle, 0, -9), (strap, 0.03, -13), (swish, 0.0, -15),
              *tinks,
              (grab, 0.16, -18), (knock, 0.165, -9),
              (click1, t_rdy, -3), (click2, t_rdy + 0.028, -2))
    x = saturate(x, 1.2)
    return _trim_head(_room(x, r, mix_db=-22))


# ==========================================================================
# IMPACTS & GORE -- real wet / crunch / wood-crack / leaf recordings (CC0,
#                   OpenGameArt) over Kenney hits and synth thumps, glued
#                   dense and loud with a look-ahead limiter
# ==========================================================================
# OpenGameArt recordings: (sources.OGA id, file pattern inside the pack)
SQUISH =("independent-nu-squish", "impsplat/impactsplat0{}.mp3.flac")
SPLAT = ("independent-nu-splatter", "extreme_splatter/{}.mp3.flac")
CRUNCH = ("independent-nu-break-crunch", "impcrunch/impactcrunch0{}.mp3.flac")
WOOD = ("independent-nu-wood-crack", "wood_impact/{}.mp3.flac")
RUSTLE = ("qubodup-rustle", "rustle/rustle{:02d}.flac")


def _seg(c, src, name, t, dur, hold, tau):
    """One hit cut out of an OpenGameArt recording (onset-aligned at ~t s,
    unity for `hold` s, then an exponential tail with time constant `tau`)."""
    oid, pattern = src
    return take(c.o(oid, pattern.format(name)), t, dur, hold=hold, tau=tau)


def _tail(x, hold, tau):
    """Shorten a clip's tail: unity for `hold` s, then exponential decay."""
    t = times(len(x))
    return x * np.where(t < hold, 1.0, np.exp(-(t - hold) / tau))


def _onset(x, thr=0.2, pre=0.001):
    """Trim a clip's lead-in so its first transient (first sample over
    thr x peak) lands `pre` s after the start (short fade-in, no click).
    Kenney's rpg 'chop' has ~48 ms of near-silence before the hit and the
    impactPunch_heavy clips ~18 ms: untrimmed, their hit lands late and
    reads as a second transient."""
    i = int(np.argmax(np.abs(x) > thr * np.max(np.abs(x))))
    return fade(x[max(0, i - n_of(pre)):], 0.0008, 0.0)


def _hf_crack(c, src, name, t, hp=1600.0, search=0.04, pre=0.003, hold=0.006, tau=0.015):
    """A short splinter 'tick' from a crack recording, aligned on its
    high-passed transient (not the full-band onset): the highpassed peak
    within `search` s of the onset sits `pre` s after the start, unity for
    `hold` s after that, then an exponential tail (tau)."""
    oid, pattern = src
    y = highpass(take(c.o(oid, pattern.format(name)), t, 0.25, hold=1.0, tau=1.0), hp, 2)
    i = int(np.argmax(np.abs(y[: n_of(search)])))
    y = fade(y[max(0, i - n_of(pre)):], 0.001, 0.0)
    return B.unit(_tail(y, pre + hold, tau))


def _peak_seg(c, src, name, t, dur, pre=0.008, hold=0.1, tau=0.15, search=0.04):
    """A slice of a recording aligned on its LOUDEST moment (10 ms RMS max
    within +-search s of t), not its first onset: the peak lands `pre` s
    after the start, reached through a raised-cosine fade-in over `pre`.
    Used for leaf crushes, whose rustle swells for 50-90 ms before its main
    crunch (onset-aligned, that crunch reads as a second, late event)."""
    oid, pattern = src
    x = c.o(oid, pattern.format(name))
    w = n_of(0.01)
    e = np.sqrt(np.convolve(x * x, np.ones(w) / w, mode="same"))
    i0, i1 = max(0, n_of(t - search)), min(len(x), n_of(t + search))
    ip = i0 + int(np.argmax(e[i0:i1]))
    a = max(0, ip - n_of(pre))
    y = fade(x[a : a + n_of(pre + dur)], pre, 0.0)
    return B.unit(_tail(y, pre + hold, tau))


def _peak_limit(x, ceil_db=-1.3, look=0.001, release=0.035):
    """Look-ahead peak limiter: the gain is already down when a peak arrives
    (2*look ahead, raised-cosine smoothed), then recovers exponentially."""
    c = db(ceil_db)
    L = max(1, n_of(look))
    a = np.concatenate([np.abs(x), np.zeros(2 * L)])
    win = np.lib.stride_tricks.sliding_window_view(a, 2 * L + 1).max(axis=1)[: len(x)]
    tgt = np.minimum(1.0, c / np.maximum(win, 1e-12))
    rel = np.exp(-1.0 / (release * SR))
    g = np.empty_like(tgt)
    cur = 1.0
    for i, gt in enumerate(tgt):
        cur = gt if gt < cur else gt + (cur - gt) * rel
        g[i] = cur
    k = np.hanning(2 * L + 3)[1:-1]
    k /= k.sum()
    g = np.convolve(np.concatenate([np.full(L, g[0]), g, np.full(L, g[-1])]), k, mode="valid")
    return x * g[: len(x)]


def _glue(x, loud, drive=1.6, ceil_db=-1.3, passes=3):
    """Glue the layers (soft tanh saturation), then bring the result to the
    recipe's loudness target with its peaks limited under the ceiling, so
    build_audio's normaliser never has to turn the sound down (that is what
    makes a raised `loud` actually play louder and denser)."""
    x = saturate(B.unit(x), drive)
    for _ in range(passes):
        x = x * db(loud - loudness_db(x))
        x = _peak_limit(x, ceil_db)
    return x


def _grit(rng, dur, count, start=0.0, t_tau=0.05, fmin=700, fmax=5500, glen=(0.002, 0.01)):
    """Dirt / grit / fragment grains thrown up by an impact (blocks.grains)."""
    return B.grains(rng, dur, count, fmin, fmax, glen=glen, t_tau=t_tau, start=start)


@recipe("carrot_impact_dirt", variants=3, loud=-10.0)
def carrot_impact_dirt(c, v):
    """Carrot slamming into the ground: a heavy, short low thump + packed-earth
    mass thud, a hard contact smack, the grass/dirt crunch, a dirt spray and a
    few clods pattering back down."""
    r = c.rng
    p = [1.0, 0.92, 1.08][v]
    oomf = B.thump(125 * p, 58 * p, 0.018, 0.045, 0.3, partial2=0.2)
    mass = _tail(lowpass(c.k("impact-sounds", f"impactSoft_heavy_00{[0, 2, 4][v]}", speed=1.2), 800, 2),
                 0.03, 0.05)
    thud = c.k("impact-sounds", f"impactSoft_medium_00{v}")
    crunch = highpass(c.k("impact-sounds", f"footstep_grass_00{v + 1}", speed=1.15), 150, 2)
    grit = highpass(c.k("impact-sounds", f"footstep_snow_00{[1, 2, 4][v]}", speed=1.25), 250, 2)
    smack = B.burst(r, 0.06, 1400 * p, 0.6, 0.006, attack=0.0004)
    spray = _grit(r, 0.45, 34, start=0.003, t_tau=0.045)
    clods = _grit(r, 0.5, 12, start=0.07, t_tau=0.1, fmin=400, fmax=2600, glen=(0.004, 0.014))
    puff = B.lp_burst(r, 0.3, 1600, 0.05, attack=0.002)
    x = mix(0.45, (oomf, 0, 0), (mass, 0, -3), (thud, 0, -6), (crunch, 0.002, 1), (grit, 0.004, -3),
            (smack, 0, -7), (spray, 0.004, -3), (clods, 0, -12), (puff, 0.002, -12))
    return _glue(x, -10.0, drive=1.8)


@recipe("carrot_impact_wood", variants=3, loud=-12.5)
def carrot_impact_wood(c, v):
    """A projectile 'THOCK' into a tree / log: hard contact click, a short,
    dense woody knock (paired, quickly damped modes = no marimba ring) with a
    firm low body and a small real splinter crack fused into the hit (one
    event, no 'tok... TIK')."""
    r = c.rng
    s = [1.0, 0.89, 1.12][v]
    knock = B.struck(r, [(410 * s, 0.03, 1.0), (455 * s, 0.022, 0.6), (980 * s, 0.02, 0.45),
                         (1150 * s, 0.014, 0.28), (1700 * s, 0.011, 0.22), (2700 * s, 0.007, 0.14),
                         (3900 * s, 0.004, 0.08)], 0.25)
    # the chop's hit sits ~48 ms into the Kenney clip: trim it onto the knock
    chop = _onset(c.k("rpg-audio", "chop", speed=[1.0, 0.92, 1.1][v]))
    body = B.thump(190 * s, 120 * s, 0.015, 0.035, 0.2)
    thud = B.lp_burst(r, 0.15, 700, 0.025, attack=0.0008)
    click = B.crack(r, 0.0012, 3000)
    # splinter: aligned on its high-passed crack, peak ~10 ms after the knock
    name, t = [("crack02", 0.14), ("crack06", 0.16), ("crack04", 0.22)][v]
    split = _hf_crack(c, WOOD, name, t)
    bits = _grit(r, 0.25, 9, start=0.012, t_tau=0.035, fmin=2500, fmax=8000, glen=(0.001, 0.004))
    crunch = highpass(c.k("impact-sounds", f"impactWood_light_00{(v + 1) % 5}", speed=1.35), 500, 2)
    x = mix(0.3, (knock, 0, 0), (chop, 0, -6), (body, 0, -3), (thud, 0, -4), (click, 0, -13),
            (split, 0.007, -14), (bits, 0, -17), (crunch, 0.002, -16))
    return _glue(x, -12.5, drive=1.4)


@recipe("carrot_impact_flesh", variants=3, loud=-11.0)
def carrot_impact_flesh(c, v):
    """Hit-confirm: a solid punch with a short, wet, meaty low-mid squelch.
    No slime bubbles, no droplet plinks, no resonant 'bloop' sweep."""
    r = c.rng
    src, name, t = [(SQUISH, 3, 0.1), (SQUISH, 6, 0.05), (SPLAT, "crack11", 1.09)][v]
    sq = varispeed(_seg(c, src, name, t, 0.32, hold=0.04, tau=0.06), [0.88, 0.85, 0.9][v])
    sq = peak_eq(lowpass(highpass(sq, 140, 2), 1800, 2), 420, 6.0, q=0.8)
    punch = _tail(c.k("impact-sounds", f"impactPunch_medium_00{v}", speed=0.95), 0.05, 0.05)
    low = B.thump(155, 75, 0.02, 0.045, 0.25)
    # broad (low-Q, so no resonant 'bloop') low-mid formant sweep: the "schlp"
    shlp = B.squelch(r, 0.16, [(0, 280), (0.035, [700, 620, 760][v]), (0.16, 330)], q=1.1,
                     amp_pts=[(0, 0), (0.006, 1), (0.06, 0.55), (0.16, 0)])
    shlp = lowpass(shlp, 1400, 2)
    squish = lowpass(B.wet_grains(r, 0.3, 46, 260, 900, glen=(0.008, 0.024), t_tau=0.035, start=0.004),
                     1400, 2)
    smack = B.burst(r, 0.05, 1700, 0.7, 0.004, attack=0.0004)
    x = mix(0.3, (low, 0, [-3, 0, -3][v]), (punch, 0, -5), (sq, 0.006, 4), (shlp, 0.004, -2),
            (squish, 0, -5), (smack, 0, -13))
    return _glue(x, -11.0, drive=1.5)


@recipe("headshot", variants=2, loud=-11.0)
def headshot(c, v):
    """Comedic hollow BONK: wood knock + falling bonk + a little cork pop."""
    r = c.rng
    if v == 0:
        knock = c.k("impact-sounds", "impactWood_light_001", speed=0.75)
        bk, pop = B.bonk(r, 620, 380), B.cork_pop(r, 320, 950)
    else:  # a little lower and rounder
        knock = highpass(c.k("impact-sounds", "impactWood_light_003", speed=0.72), 60, 2)
        bk, pop = B.bonk(r, 575, 350), B.cork_pop(r, 300, 880)
    return mix(0.55, (bk, 0, 0), (knock, 0, -6), (pop, 0.005, -7))


@recipe("gore_splat", variants=3, loud=-9.5)
def gore_splat(c, v):
    """Hard body hit (fast low thump + heavy punch + smack) with the meaty
    splat and squish on top and a few dark scattered plips."""
    r = c.rng
    oomf = B.thump([118, 105, 126][v], 55, 0.025, 0.07, 0.4, partial2=0.15)
    punch = _tail(lowpass(c.k("impact-sounds", f"impactPunch_heavy_00{v}"), 4500, 2), 0.08, 0.08)
    smack = B.burst(r, 0.06, 2000, 0.6, 0.005, attack=0.0003)
    src, name, t = [(SQUISH, 1, 0.055), (SQUISH, 8, 0.385), (SPLAT, "crack12", 0.15)][v]
    splat = _seg(c, src, name, t, 0.55, hold=0.08, tau=0.12)
    splat = peak_eq(lowpass(highpass(splat, 150, 2), [3200, 4500, 4000][v], 2), 600, 3.0, q=0.8)
    wet = B.squelch(r, 0.24, [(0, 380), (0.05, 1100), (0.24, 520)], q=1.6)
    squish = B.wet_grains(r, 0.5, 40, 250, 1300, glen=(0.008, 0.03), t_tau=0.07, start=0.01)
    drops = B.droplets(r, 0.6, 7, t_tau=0.12, start=0.08, fmin=500, fmax=1300)
    x = mix(0.6, (oomf, 0, [4, 2, 4][v]), (punch, 0, -2), (smack, 0, -10),
            (splat, 0.004, [-2, 1, -1][v]), (wet, 0.006, -12), (squish, 0, -9), (drops, 0, -22))
    return _glue(x, -9.5, drive=1.7)


@recipe("gore_limb_pop", variants=3, loud=-11.0)
def gore_limb_pop(c, v):
    r = c.rng
    p = [1.0, 0.85, 1.15][v]
    pop = B.cork_pop(r, 280 * p, 800 * p, dur=0.15, noise_db=-5)
    low = B.thump(140 * p, 70, 0.03, 0.05, 0.2)
    slime = c.k("sci-fi-sounds", "slime_000", speed=1.2)
    drops = B.droplets(r, 0.6, 8, t_tau=0.1, start=0.05)
    fluff = B.whoosh(r, 0.12, 2000, 4200, q=1.0, peak=0.3)
    return mix(0.6, (pop, 0, 0), (low, 0, -6), (slime, 0.03, -7), (drops, 0, -12), (fluff, 0.02, -15))


@recipe("body_fall", variants=3, loud=-12.5)
def body_fall(c, v):
    """A body collapsing onto the forest floor: the heavy soft mass thud
    crushing dry leaves and grass right at t=0 (the game fires it on the
    touchdown frame), a limb slapping down just after, and a small settle of
    an arm flopping down (un-pitched, no bounce)."""
    r = c.rng
    # crossover layering: the sine 'weight' owns the sub, the mass clip and
    # the flesh hit sit above ~110 Hz (overlapping lows beat against each
    # other and re-swell 30-50 ms in); front-loaded, decaying only after
    mass = _tail(highpass(c.k("impact-sounds", f"impactSoft_heavy_00{[1, 3, 0][v]}"), 110, 4), 0.02, 0.07)
    weight = B.thump([82, 76, 88][v], 50, 0.04, 0.07, 0.5)
    # impactPunch_heavy has ~18 ms of lead-in: trim it onto the thud
    flesh = _onset(highpass(lowpass(c.k("impact-sounds", f"impactPunch_heavy_00{[3, 4, 1][v]}", speed=0.9),
                                    1500, 2), 110, 4))
    # dry-leaf crush, aligned on the rustle's main crunch (peak ~8 ms in)
    rec, t = [(15, 0.25), (16, 0.27), (18, 0.235)][v]
    leaves = _peak_seg(c, RUSTLE, rec, t, 0.6, pre=0.008, hold=0.08, tau=0.14, search=0.03)
    leaves = lowpass(highpass(leaves, 300, 2), 7000, 1)
    grass = highpass(c.k("impact-sounds", f"footstep_grass_00{[1, 2, 3][v]}", speed=0.92), 150, 2)
    crush = highpass(c.k("impact-sounds", f"footstep_snow_00{[2, 4, 1][v]}", speed=0.85), 300, 2)
    twig = B.crackle(r, 0.25, 30, 1800, 6000, glen=(0.001, 0.004))
    t_limb = [0.06, 0.05, 0.07][v]       # a limb slaps down just after the torso
    limb = lowpass(c.k("impact-sounds", f"impactSoft_medium_00{v}", speed=1.1), 1600, 2)
    t2 = [0.3, 0.26, 0.34][v]            # an arm flops down
    flop = bandpass(c.k("impact-sounds", f"impactSoft_medium_00{(v + 2) % 5}", speed=1.25), 420, 0.8)
    rest = _seg(c, RUSTLE, [13, 17, 9][v], [0.26, 0.13, 0.07][v], 0.4, hold=0.05, tau=0.1)
    rest = lowpass(highpass(rest, 400, 2), 7000, 1)
    x = mix(1.0, (mass, 0, 0), (weight, 0, -3), (flesh, 0.001, -6), (leaves, 0, [0, -2, -4][v]),
            (grass, 0, 0), (crush, 0.003, -5), (twig, 0.01, -14), (limb, t_limb, [-15, -15, -18][v]),
            (flop, t2, -16), (rest, t2 - 0.01, [-20, -17, -13][v]))
    return _glue(x, -12.5, drive=1.4)


# ==========================================================================
# MOVEMENT -- real dry-leaf footsteps (TinyWorlds, CC0) over soft Kenney
#             pads, synthesized grass-blade crackle
# ==========================================================================
TW = "tinyworlds-different-steps"
# loud crunch events (file, approx onset s) in the two leaf recordings
_LEAF_EVENTS = [("leaves01.ogg", 0.05), ("leaves02.ogg", 0.03), ("leaves01.ogg", 0.15),
                ("leaves02.ogg", 0.09), ("leaves01.ogg", 0.12), ("leaves02.ogg", 0.17),
                ("leaves01.ogg", 0.23)]
_CARPET = [0, 1, 3, 0, 1]  # distinct Kenney carpet pads (001=002, 003=004)
# footstep crunch cuts: (file, onset s, speed). Each variant gets its own crackle
# event; cuts that share a recording are >= 66 ms apart, so with the short
# window below (12 ms hold, 18 ms tail) no two variants share audible audio.
_STEP_LEAF = [("leaves01.ogg", 0.048, 1.00), ("leaves02.ogg", 0.026, 1.06),
              ("leaves01.ogg", 0.152, 0.92), ("leaves02.ogg", 0.092, 1.12),
              ("leaves01.ogg", 0.226, 1.04)]


def _L(x, rel=0.0):
    """Scale a layer to a K-weighted loudness of (-20 + rel) dB, so layer
    gains in mix() are perceptual balances rather than peak ratios."""
    return x * db(-20.0 + rel - loudness_db(x))


def _leaf(c, i, dur=0.14, hold=0.03, tau=0.04, hp=1100.0, speed=1.0):
    """One real dry-leaf crunch cut from the TinyWorlds recordings."""
    f, t = _LEAF_EVENTS[i % len(_LEAF_EVENTS)]
    x = highpass(c.o(TW, f), hp, 2)
    if speed != 1.0:
        x = varispeed(x, speed)
        t /= speed
    return fade(take(x, t, dur, hold=hold, tau=tau), 0.002, 0.006)


def _blades(r, dur=0.12, count=40, fmin=2200.0, fmax=8500.0, t_tau=0.025, glen=(0.0008, 0.004)):
    """Crisp grass-blade crackle (tiny band-passed grains, front-loaded)."""
    return B.grains(r, dur, count, fmin, fmax, glen=glen, t_tau=t_tau)


def _swish(r, dur=0.07, fc=4500.0, q=0.9, attack=0.004, tau=0.02):
    """Blades brushing past fur: short band of airy noise."""
    n = n_of(dur)
    return B.unit(bandpass(white(n, r), fc, q)) * env_exp(n, attack, tau)


def _pad(r, f0=150.0, f1=85.0, tau=0.035, pat_fc=900.0):
    """Soft furry paw pad: low sine thump + a muffled noise 'pat'."""
    body = B.thump(f0, f1, 0.012, tau, tau * 6)
    pat = highpass(B.lp_burst(r, 0.06, pat_fc, 0.012, attack=0.0015), 130, 2)
    return B.unit(mix(0, (_L(body), 0, -2), (_L(pat), 0, 0)))


def _flutter(r, dur, rate_pts, fc=1500.0, tau=0.16, jit=0.3):
    """Fabric / leaf flapping: irregular train of small noise 'flaps' whose
    rate follows rate_pts and whose level decays with tau."""
    out = np.zeros(n_of(dur) + n_of(0.05))
    t = 0.0
    ts, rs = zip(*rate_pts)
    while t < dur:
        rate = np.exp(np.interp(t, ts, np.log(rs)))
        L = n_of(r.uniform(0.012, 0.022))
        g = bandpass(white(L + 256, r), fc * r.uniform(0.7, 1.4), 1.1)[:L]
        g = B.unit(g) * env_exp(L, 0.0008, L / SR / 3.5)
        i = n_of(t)
        out[i:i + L] += g * r.uniform(0.45, 1.0) * np.exp(-t / tau)
        t += max(0.02, (1.0 / rate) * (1 + jit * r.standard_normal()))
    return out[: n_of(dur)]


def _cut_at(x, t, dur, hold, tau, search=0.006, pre=0.004):
    """Cut one event at onset ~t s (searched within +-search s, so a
    neighbouring crackle can't capture it), `pre` s of lead-in (all but its
    last 2 ms faded up with a raised cosine), unity for `hold` s after the
    onset, then an exponential tail. Returns (unit-peak cut, source start index)."""
    i = n_of(t)
    w0, w1 = max(0, i - n_of(search)), min(len(x), i + n_of(search))
    seg = np.abs(x[w0:w1])
    on = w0 + int(np.argmax(seg > 0.3 * seg.max()))
    a = max(0, on - n_of(pre))
    y = x[a: a + n_of(pre + dur)].copy()
    tt = times(len(y))
    y *= np.where(tt < pre + hold, 1.0, np.exp(-(tt - pre - hold) / tau))
    return fade(B.unit(y), max(0.002, pre - 0.002), 0.006), a


def _step_leaf(c, v, hold=0.012, tau=0.018, dur=0.12, hp=450.0, lead=0.010):
    """Footstep crunch: the variant's own crackle event, short and crisp, with
    `lead` s of the quieter rustle before it swelling in (the leaves start to
    give as the weight comes on)."""
    f, t, sp = _STEP_LEAF[v % len(_STEP_LEAF)]
    x = highpass(c.o(TW, f), hp, 2)
    y, _ = _cut_at(x, t, dur * sp, hold * sp, tau * sp, pre=(0.004 + lead) * sp)
    return varispeed(y, sp) if sp != 1.0 else y


@recipe("footstep_grass", variants=5, loud=-14.5, src="mixed")
def footstep_grass(c, v):
    """Paw pad, then the dry grass/leaves crunch under the weight ~45 ms later.

    Enemy steps behind the listener go through SFXBehind (1.7 kHz low-pass):
    the crunch is mostly lost there, so the pad must carry the rear step. With
    pad and crunch in separate 50 ms windows, the pad sets the rear level and
    the crunch sets the front level, so each can be loud without masking the other.
    """
    r = c.rng
    pre = 0.004  # pre-roll: finish()'s 1.5 ms fade-in must not eat the paw's attack
    gap = 0.040  # paw lands ... blades + leaf crackle (the leaf's own onset is ~6 ms
    lead = 0.010  # later), after a 10 ms swell of the rustle that leads into it
    # soft paw pad: Kenney grass thud (minus its sub-sonic DC) + a carpet pad,
    # kept tight (12 ms, then a 10 ms tail) so it doesn't smear into the crunch
    thud = c.k("impact-sounds", f"footstep_grass_00{v}", speed=1.12, dur=0.2)
    thud = lowpass(highpass(thud, 110, 2), 2200, 1)
    carpet = c.k("impact-sounds", f"footstep_carpet_00{_CARPET[v]}",
                 speed=[1.25, 1.3, 1.2, 1.35, 1.15][v])
    pad = B.unit(mix(0, (_L(thud), 0, 0), (_L(highpass(carpet, 120, 2)), 0, -2)))
    tt = times(len(pad))
    pad = pad * np.where(tt < 0.012, 1.0, np.exp(-(tt - 0.012) / 0.010))
    # faint 500-1600 Hz crush of stalks folding, between pad and crunch
    crush = B.grains(r, 0.08, 20, 500.0, 1600.0, glen=(0.002, 0.007), t_tau=0.02)
    # crunchy dry grass / leaves (crisp 2-8 kHz = easy to locate), dense on its
    # own bus so the compressor doesn't duck the pad
    leaf = lowpass(_step_leaf(c, v, lead=lead), 10000, 1)
    blades = _blades(r, 0.1, 36, t_tau=0.016)
    sw = _swish(r, 0.06, 4200 + 400 * v, 0.9, 0.003, 0.014)
    crunch = squash(mix(0, (_L(leaf), 0.002, 0), (_L(blades), lead, -7), (_L(sw), lead, -12)),
                    -6.0, 3.0)
    x = mix(0.16, (_L(pad), pre, -1.0), (_L(crush), pre + 0.018, -12.0),
            (_L(crunch), pre + gap - lead, 0.0))
    return saturate(squash(x, -2.0, 1.5), 1.4)


@recipe("hop", variants=5, loud=-16.0, src="mixed")
def hop(c, v):
    r = c.rng
    # rabbit landing: front paws touch, hind feet pad down a beat later,
    # then a light brush of grass/leaves
    gap = [0.032, 0.026, 0.038, 0.030, 0.035][v]
    front = _pad(r, 260 + 15 * v, 160, 0.014, 1300)
    hind = _pad(r, 210 + 10 * v, 120, 0.022, 1000)
    soft = c.k("impact-sounds", f"footstep_carpet_00{_CARPET[v]}",
               speed=[1.15, 1.2, 1.1, 1.3, 1.05][v])
    soft = highpass(soft, 100, 2)
    leaf = _leaf(c, v + 2, dur=0.11, hold=0.015, tau=0.03, hp=1400,
                 speed=[1.05, 1.15, 0.98, 1.1, 1.2][v])
    leaf = lowpass(leaf, 9000, 1)
    blades = _blades(r, 0.1, 18, t_tau=0.02)
    x = mix(0.2, (_L(front), 0, -7), (_L(soft), gap - 0.002, -1), (_L(hind), gap, -3),
            (_L(leaf), gap + 0.004, -3), (_L(blades), gap + 0.002, -11))
    return squash(x, -10.0, 3.0)  # rounder, less clicky when it repeats


@recipe("jump", variants=3, loud=-19.0)
def jump(c, v):
    r = c.rng
    sw = B.whoosh(r, 0.26, 400, 1800 + 200 * v, q=1.5, peak=0.3)
    scuff = c.k("impact-sounds", f"footstep_grass_00{v + 2}", speed=1.3)
    return mix(0.3, (sw, 0, 0), (scuff, 0, -6))


@recipe("land", variants=3, loud=-17.0)
def land(c, v):
    r = c.rng
    thud = c.k("impact-sounds", f"impactSoft_medium_00{v + 1}")
    leaves = c.k("impact-sounds", f"footstep_grass_00{(v + 2) % 5}")
    bits = B.grains(r, 0.3, 8, 2000, 5000, t_tau=0.04)
    return mix(0.35, (thud, 0, 0), (leaves, 0, -2), (bits, 0.005, -14))


@recipe("glider_open", variants=2, loud=-10.0, src="mixed")
def glider_open(c, v):
    r = c.rng
    tp = 0.085  # the canopy catches air here
    # unfurl: leaves / petals rustle open, rising swish
    rise = B.whoosh(r, tp + 0.02, 900, 3800, q=1.0, peak=0.9)
    crinkle = _leaf(c, 3 + v, dur=0.14, hold=0.05, tau=0.05, hp=1500, speed=1.1)
    # the pop: real fabric snap + book-slap 'thwap' + synthesized crack, snap, whump
    cloth = c.k("rpg-audio", ["cloth2", "cloth4"][v])
    cloth = highpass(take(cloth, [0.11, 0.09][v], 0.3, hold=0.06, tau=0.08), 150, 2)
    sp = [0.82, 0.74][v]
    thwap = take(c.k("rpg-audio", "bookClose", speed=sp), 0.07 / sp, 0.16, hold=0.02, tau=0.04)
    thwap = highpass(thwap, 180, 2)
    crack = B.crack(r, 0.004, 2600)
    n = n_of(0.08)
    snap = B.unit(bandpass(white(n, r), 1100 + 200 * v, 1.4)) * env_exp(n, 0.0005, 0.016)
    whump = B.unit(mix(0, (B.thump(150 - 10 * v, 75, 0.025, 0.05, 0.3), 0, 0),
                       (B.lp_burst(r, 0.25, 400, 0.045, attack=0.003), 0, -3)))
    # second smaller snap: the canopy edge pulls taut
    n = n_of(0.06)
    snap2 = B.unit(bandpass(white(n, r), 1600, 1.2)) * env_exp(n, 0.0005, 0.012)
    # settle: flutter that slows down, and air through the canopy
    flut = _flutter(r, 0.6, [(0, 24 - 3 * v), (0.6, 11)], fc=1400 + 200 * v, tau=0.17)
    air = B.whoosh(r, 0.7, 2200, 500, q=1.0, peak=0.18)
    x = mix(0.9,
            (_L(rise), 0, -9), (_L(crinkle), 0.02, -9),
            (_L(cloth), tp - 0.004, 0), (_L(thwap), tp, -1), (_L(crack), tp, -8),
            (_L(snap), tp, -4), (_L(whump), tp + 0.004, -4),
            (_L(snap2), tp + 0.03 + 0.008 * v, -7),
            (_L(flut), tp + 0.04, -6), (_L(air), tp + 0.02, -12))
    return saturate(squash(x, -10.0, 3.0, smooth=0.008), 1.3)


# ==========================================================================
# PICKUPS / LOOT
# ==========================================================================
@recipe("pickup_ammo", variants=2, loud=-14.0)
def pickup_ammo(c, v):
    r = c.rng
    clatter = c.k("casino-audio", ["chips-handle-3", "chips-stack-3"][v])
    click = c.k("rpg-audio", "metalClick", start=0.05)
    n1 = pluck(midi_hz(69), 0.3, r)  # A4
    n2 = pluck(midi_hz(76), 0.35, r)  # E5
    return mix(0.5, (clatter, 0, -2), (click, 0.02, -6), (n1, 0.03, -9), (n2, 0.09, -8))


@recipe("pickup_health", loud=-14.0, src="synth")
def pickup_health(c, v):
    r = c.rng
    layers = []
    for i, m in enumerate([84, 88, 91, 96]):  # C6 E6 G6 C7 sparkle arpeggio
        layers.append((bell(midi_hz(m), 0.6, tau=0.25), 0.05 * i, -3 - i))
    n = n_of(0.8)
    pad = sum(additive(midi_hz(m), n, [(1, 1), (2, 0.25)]) for m in (72, 76, 79))
    pad = pad * env_pts(n, [(0, 0), (0.04, 1), (0.35, 0.6), (0.8, 0)])
    shimmer = highpass(white(n, r), 6000) * env_pts(n, [(0, 0), (0.15, 1), (0.8, 0)])
    layers += [(pad / 3, 0, -10), (B.unit(shimmer), 0, -26)]
    return mix(1.0, *layers)


@recipe("pickup_armor", loud=-14.0)
def pickup_armor(c, v):
    knock = c.k("impact-sounds", "impactWood_light_002", speed=0.9)
    clink = c.k("impact-sounds", "impactPlate_light_000", speed=1.2)
    layers = [(knock, 0, 0), (clink, 0.01, -6)]
    for i, m in enumerate([79, 86, 91]):  # G5 D6 G6
        layers.append((bell(midi_hz(m), 0.5, tau=0.18), 0.06 + 0.04 * i, -8 - i))
    return mix(0.75, *layers)


@recipe("pickup_weapon", loud=-13.0)
def pickup_weapon(c, v):
    """Metal latch + cloth grab, then a deep, warm rolled harp chord
    (G2 D3 G3 B3 -- two octaves below the old G4 D5 G5 plucks)."""
    r = c.rng
    latch = c.k("rpg-audio", "metalLatch")
    cloth = c.k("rpg-audio", "cloth4")
    notes = ((43, 0.0, 0.75), (50, -1.0, 0.65), (55, -2.0, 0.55), (59, -3.5, 0.5))  # (midi, dB, tau)
    gap, dur = 0.05, 1.05
    layers = []
    for i, (m, g, tau) in enumerate(notes):
        layers.append((B.harp_note(midi_hz(m), dur - i * gap, r, tau=tau, pos=0.3, roll=1.65, damp=2.6,
                                   attack=0.003, finger_db=-28.0, bloom=0.25), i * gap, g))
    harp = peak_eq(peak_eq(mix(dur, *layers), 210.0, 3.0, 0.9), 520.0, 1.5, 1.2)  # soundboard
    harp = reverb(harp, r, decay=0.9, mix_db=-15.0, predelay=0.015, bright=3500.0, tail=0.25)
    ref = loudness_db(latch)  # the latch click stays the first thing you hear
    return mix(1.3, (latch, 0, 0.0), (cloth, 0, -7.0), (harp, 0.045, ref - 1.0 - loudness_db(harp)))


@recipe("crate_open", loud=-13.0)
def crate_open(c, v):
    """Creaking lid + wooden knock, then a breathy wooden-flute flourish (fast
    G-major run up to a held D6 with a mordent and vibrato); the harp is only
    a soft low chord underneath the held note."""
    r = c.rng
    creak = c.k("rpg-audio", "creak3")
    lid = c.k("impact-sounds", "impactWood_medium_002", speed=0.9)
    run = (74, 76, 78, 79, 81, 83)  # D5 E5 F#5 G5 A5 B5
    notes = []
    t0 = 0.0
    for i, m in enumerate(run):
        notes.append((t0, 0.043, m, i == 0, 0.62 + 0.05 * i))
        t0 += 0.043
    notes += [(t0, 0.05, 86, True, 1.0),            # D6 (tongued arrival)
              (t0 + 0.05, 0.035, 88, False, 0.95),  # E6 mordent
              (t0 + 0.085, 0.55, 86, False, 0.92)]  # D6 held, vibrato blooms
    fl = B.flute_line(r, notes, rel=0.12)
    fl = reverb(fl, r, decay=0.8, mix_db=-15.0, predelay=0.012, bright=6000.0, tail=0.3)
    hint = B.harp_roll(((55, 0.0), (62, -2.0), (67, -3.0)), r, 0.9, 0.03, tau=0.45,
                       pos=0.35, roll=1.8, attack=0.004, finger_db=-36.0)
    n = n_of(0.7)
    shimmer = B.unit(highpass(white(n, r), 6500)) * env_pts(n, [(0, 0), (0.1, 1), (0.7, 0)])
    T = 0.33  # flute enters just after the lid knock (so neither masks the other)
    ref = loudness_db(lid)  # balance by loudness, relative to the lid knock

    def at(x, rel_db):
        return rel_db + ref - loudness_db(x)

    return mix(2.0, (creak, 0, at(creak, -3.0)), (lid, 0.28, 0.0), (fl, T, at(fl, 0.0)),
               (hint, T + t0, at(hint, -16.0)), (shimmer, T + t0, at(shimmer, -30.0)))


@recipe("armor_break", variants=2, loud=-10.5)
def armor_break(c, v):
    """The acorn-shell armour cracking apart: a sharp fracture snap, a short
    hard nut-shell knock, a dense crunch, splintering, a dull body hit
    underneath, and brittle debris crackle as the bits fall."""
    r = c.rng
    s = [1.0, 0.9][v]
    snap = B.crack(r, 0.0025, 2600)
    shell = B.struck(r, [(650 * s, 0.024, 1.0), (1290 * s, 0.016, 0.7), (2100 * s, 0.01, 0.5),
                         (3200 * s, 0.006, 0.3)], 0.15, exc_ms=0.8)
    crunch = _seg(c, CRUNCH, [3, 1][v], [0.11, 0.08][v], 0.6, hold=0.07, tau=0.11)
    crunch = lowpass(highpass(crunch, 250, 2), 7000, 1)
    name, t = [("crack03", 0.17), ("crack01", 0.22)][v]
    splint = highpass(_seg(c, WOOD, name, t, 0.45, hold=0.06, tau=0.1), 900, 2)
    hit = lowpass(c.k("impact-sounds", f"impactWood_heavy_00{[1, 3][v]}"), 1400, 2)
    body = B.thump(160, 80, 0.02, 0.05, 0.3)
    crackle = B.crackle(r, 0.5, 70, 2500, 9000, glen=(0.001, 0.005))
    crackle = crackle * env_pts(len(crackle), [(0, 1.0), (0.12, 0.7), (0.5, 0.0)])
    bits = _grit(r, 0.8, 14, start=0.16, t_tau=0.14, fmin=1800, fmax=6000, glen=(0.001, 0.004))
    x = mix(0.8, (crunch, 0.004, 0), (snap, 0, -6), (shell, 0.001, -2), (splint, 0.012, -9),
            (hit, 0, -2), (body, 0, -3), (crackle, 0.02, -14), (bits, 0, -15))
    return _glue(x, -10.5, drive=1.6)


# ==========================================================================
# CRITTER VOICES -- deep, gritty small-animal voices (B.critter_voice:
#                   subharmonic growl, jitter, chirr trills, vocal fry)
# ==========================================================================
@recipe("hurt_squeak", variants=6, loud=-14.0, src="synth")
def hurt_squeak(c, v):
    r = c.rng
    if v == 0:  # "yowp!" -- sharp yelp
        y = B.critter_voice(r, 0.24, [(0, 380), (0.035, 620), (0.09, 560), (0.24, 330)],
                            [(0, "uh"), (0.04, "a"), (0.15, "aw"), (0.24, "o")],
                            sub_pts=[(0, 0.1), (0.05, 0.35), (0.24, 0.5)],
                            amp_pts=[(0, 0), (0.012, 1), (0.1, 0.8), (0.24, 0)])
        return mix(0.26, (y, 0, 0), (B.tongue_click(r, 1800, 1.0, 0.004), 0, -14))
    if v == 1:  # "ak-ak-ak-ak" -- pained chatter
        return B.chitter(r, [0, 0.062, 0.12, 0.175], [560, 600, 540, 470],
                         gains=[0, -1, -2, -4], sub_pts=[(0, 0.3), (0.05, 0.3)], jitter=0.02)
    if v == 2:  # "rrrah!" -- growly chirr
        return B.critter_voice(r, 0.27, [(0, 300), (0.04, 440), (0.14, 400), (0.27, 250)],
                               [(0, "a"), (0.15, "a"), (0.27, "uh")],
                               trill=(34.0, [(0, 0.2), (0.05, 0.65), (0.27, 0.7)]),
                               sub_pts=[(0, 0.4), (0.27, 0.7)], breath=0.18, shimmer=0.2)
    if v == 3:  # "hnn-YIP" -- grunt flowing into a yelp
        g = B.critter_voice(r, 0.08, [(0, 160), (0.07, 185)], [(0, "uh"), (0.08, "uh")],
                            fry_pts=[(0, 0.7), (0.08, 0.5)], breath=0.2,
                            amp_pts=[(0, 0), (0.01, 1), (0.08, 0.4)])
        y = B.critter_voice(r, 0.18, [(0, 450), (0.03, 720), (0.18, 400)],
                            [(0, "ae"), (0.06, "a"), (0.18, "o")], sub_pts=[(0, 0.25), (0.18, 0.4)],
                            amp_pts=[(0, 0), (0.01, 1), (0.08, 0.8), (0.18, 0)])
        return mix(0.26, (g, 0, -5), (y, 0.065, 0))
    if v == 4:  # "eeyowr" -- raspy whine, an octave+ below the old squeal
        return B.critter_voice(r, 0.34, [(0, 480), (0.05, 640), (0.2, 560), (0.34, 360)],
                               [(0, "e"), (0.08, "ae"), (0.2, "a"), (0.34, "o")],
                               vib=(9.0, 0.01, 0.04), sub_pts=[(0, 0.15), (0.34, 0.45)],
                               shimmer=0.25, breath=0.14)
    # v == 5: "ngh!" -- low strained grunt with a huff
    g = B.critter_voice(r, 0.22, [(0, 230), (0.04, 310), (0.22, 180)], [(0, "uh"), (0.22, "o")],
                        fry_pts=[(0, 0.3), (0.12, 0.4), (0.22, 0.9)], sub_pts=[(0, 0.3), (0.22, 0.4)],
                        breath=0.22, amp_pts=[(0, 0), (0.01, 1), (0.12, 0.75), (0.22, 0)])
    huff = B.exhale(r, 0.12, lp=1500, tau=0.03)
    return mix(0.24, (g, 0, 0), (huff, 0, -12))


@recipe("death_squeak", variants=3, loud=-14.0, src="synth")
def death_squeak(c, v):
    r = c.rng
    if v == 0:  # long falling cry that runs out of breath and creaks out
        w = B.critter_voice(r, 1.15, [(0, 400), (0.06, 640), (0.2, 600), (0.55, 420), (0.95, 240), (1.15, 170)],
                            [(0, "uh"), (0.06, "a"), (0.4, "aw"), (0.8, "o"), (1.15, "oo")],
                            vib=(6.5, 0.008, 0.05), sub_pts=[(0, 0.15), (0.5, 0.3), (1.15, 0.75)],
                            fry_pts=[(0, 0), (0.8, 0.05), (1.15, 0.6)], fry_rate=((0, 70), (1.15, 40)),
                            shimmer=0.18, amp_pts=[(0, 0), (0.015, 1), (0.25, 0.9), (0.8, 0.55), (1.15, 0)])
        return mix(1.4, (w, 0, 0), (B.exhale(r, 0.4), 1.0, -13))
    if v == 1:  # "ack! ... ooowww" + a last croak
        a = B.critter_voice(r, 0.2, [(0, 420), (0.03, 700), (0.2, 450)], [(0, "ae"), (0.2, "a")],
                            sub_pts=[(0, 0.3), (0.2, 0.3)], amp_pts=[(0, 0), (0.01, 1), (0.1, 0.8), (0.2, 0)])
        b = B.critter_voice(r, 0.8, [(0, 520), (0.08, 560), (0.4, 380), (0.8, 190)],
                            [(0, "a"), (0.3, "aw"), (0.8, "u")], vib=(5.5, 0.01, 0.035),
                            trill=(28.0, [(0, 0), (0.4, 0.25), (0.8, 0.6)]),
                            sub_pts=[(0, 0.2), (0.8, 0.6)],
                            amp_pts=[(0, 0), (0.03, 1), (0.45, 0.75), (0.8, 0)])
        croak = B.critter_voice(r, 0.16, [(0, 125), (0.16, 90)], [(0, "o"), (0.16, "uh")],
                                fry_pts=[(0, 0.9), (0.16, 0.9)], fry_rate=((0, 45), (0.16, 30)), breath=0.25,
                                amp_pts=[(0, 0), (0.015, 1), (0.16, 0)])
        return mix(1.3, (a, 0, 0), (b, 0.27, -1), (croak, 1.04, -7), (B.exhale(r, 0.3), 1.12, -15))
    # v == 2: shocked stutter, then a wobbly cartoon "drop" in a low gritty voice
    k = B.chitter(r, [0, 0.055, 0.11], [620, 660, 600], gains=[0, -1, -2],
                  sub_pts=[(0, 0.3), (0.05, 0.3)], jitter=0.02)
    w = B.critter_voice(r, 0.95, [(0, 660), (0.05, 700), (0.35, 480), (0.75, 230), (0.95, 140)],
                        [(0, "ae"), (0.2, "a"), (0.6, "o"), (0.95, "oo")], vib=(7.0, 0.02, 0.08),
                        sub_pts=[(0, 0.2), (0.95, 0.8)], fry_pts=[(0, 0), (0.6, 0), (0.95, 0.7)],
                        fry_rate=((0, 60), (0.95, 35)),
                        amp_pts=[(0, 0), (0.02, 1), (0.5, 0.75), (0.95, 0)])
    return mix(1.4, (k, 0, -1), (w, 0.17, 0), (B.exhale(r, 0.35), 1.08, -14))


# ==========================================================================
# STORM / WIND / AMBIENCE (loops are seamless)
# ==========================================================================
@recipe("wind_loop", loud=-22.0, src="synth", loop=True)
def wind_loop(c, v):
    r = c.rng
    L, X = 8.0, 1.0
    tot = L + X
    n = n_of(tot)
    gust = 0.5 + 0.5 * smooth_rand(n, r, 0.5, period=L)
    whis = smooth_rand(n, r, 0.3, period=L)
    hop = 512

    def g(t, f):
        i = np.clip((t[:, 0] * SR).astype(int), 0, n - 1)
        gu = gust[i][:, None]
        fc = 450 + 900 * gu
        body = (0.35 + 0.65 * gu) / np.sqrt(1 + (f / fc) ** 2)
        fw = (700 + 250 * whis[i])[:, None]
        whistle_ = 0.35 * gu ** 2 * (bp_gain(f, fw, 18) + 0.6 * bp_gain(f, fw * 1.52, 22))
        return body + whistle_ + 0.04

    x = stft_filter(colored(n, r, -3), g, hop=hop)
    x = highpass(x, 60)
    return make_loop(x, L, X)


def _k_rms(x):
    """K-weighted RMS (linear) -- balance layers by how loud they sound."""
    return np.sqrt(np.mean(k_weight(x) ** 2)) + 1e-12


def storm_layers(r, debug=False):
    """All storm_loop layers, each exactly periodic in L and balanced by
    K-weighted loudness relative to the thorny crackle (0 dB)."""
    L = 10.0
    N = n_of(L)
    t = times(N)

    # ---- rumble: deep brown-noise roll < 100 Hz with slow swells and surges,
    #      lightly driven so its 2nd/3rd harmonics carry it on small speakers
    swell = 0.5 + 0.5 * smooth_rand(N, r, 0.35, period=L)
    surge = np.clip(smooth_rand(N, r, 0.9, period=L), 0, 1) ** 1.5
    rum = circ_filter(colored(N, r, -6), lambda f: lp_mag(95, 3)(f) * hp_mag(28, 2)(f))
    rum = B.unit(rum) * (0.4 + 0.35 * swell + 0.6 * surge)
    rum = np.tanh(2.5 * B.unit(rum)) / np.tanh(2.5)
    rum = circ_filter(rum, lp_mag(240, 2))

    # ---- wind swirl (moving band-pass, darker than before)
    lfo2 = smooth_rand(N, r, 0.25, period=L)
    gust = 0.5 + 0.5 * smooth_rand(N, r, 0.4, period=L)

    def gw(tt, f):
        i = np.clip((tt[:, 0] * SR).astype(int), 0, N - 1)
        fc = (560 + 380 * lfo2[i])[:, None]
        return bp_gain(f, fc, 1.3)

    swirl = B.unit(circ_stft(colored(N, r, -3), gw)) * (0.35 + 0.65 * gust)

    # ---- ominous hum: A1/Bb1 semitone rub + Eb2 tritone + A2, all multiples of
    #      1/L Hz (exactly periodic); a slow formant sweep makes it 'breathe'
    throb = 0.7 + 0.3 * np.sin(B.TAU * 0.5 * t - 1.0)  # 5 slow throbs per loop
    hum = (saw_bl(55.0, N, max_h=14) + 0.85 * saw_bl(58.3, N, max_h=14)
           + 0.6 * saw_bl(77.8, N, max_h=10) + 0.4 * saw_bl(110.0, N, max_h=8))
    hum = circ_filter(hum, lp_mag(650, 2))
    sweep = 0.5 + 0.5 * np.sin(B.TAU * 0.2 * t + 0.6)  # 2 sweeps per loop

    def gh(tt, f):
        i = np.clip((tt[:, 0] * SR).astype(int), 0, N - 1)
        fc = (170 + 260 * sweep[i])[:, None]
        return 0.35 + bp_gain(f, fc, 2.2)

    hum = B.unit(circ_stft(hum, gh)) * throb
    sing = (np.sin(B.TAU * 440.0 * t) + 0.8 * np.sin(B.TAU * 466.2 * t + 1.0)
            + 0.4 * np.sin(B.TAU * 311.1 * t + 2.0))
    sing = B.unit(sing) * np.clip(smooth_rand(N, r, 0.3, period=L), 0, 1) ** 2

    # ---- thorny crackle: waves of fine crackle, coarse woody crackle, twig
    #      snaps, thorn scrapes and vine whips, in a little bramble reverb
    waves = 0.3 + 0.7 * np.clip(0.45 + smooth_rand(N, r, 1.6, period=L), 0, 1)
    fine = B.unit(B.crackle(r, L, 110, 1800, 7500, period=L)) * waves
    coarse = B.unit(B.crackle(r, L, 26, 900, 3200, glen=(0.004, 0.018), period=L))
    ev = np.zeros(N + n_of(0.6))

    def put(sig, t0, g):
        i0 = n_of(t0)
        ev[i0:i0 + len(sig)] += sig * g

    for k in range(18):  # twig snaps, spread over the loop (no gap at the seam)
        put(B.twig_snap(r), (k + r.uniform(0.1, 0.9)) * L / 18, r.uniform(0.45, 1.0))
    for k in range(7):  # thorn scrapes
        put(B.thorn_scrape(r, r.uniform(0.12, 0.3)), (k + r.uniform(0.1, 0.7)) * L / 7, r.uniform(0.5, 0.9))
    snaps = fold_circular(ev, L)
    whips = np.zeros(N + n_of(0.5))
    for t0 in (0.9, 2.8, 5.1, 7.0, 8.9):
        w = B.whoosh(r, 0.24, 3400, 750, q=1.6, peak=0.25)
        i0 = n_of(t0 + r.uniform(-0.2, 0.2))
        whips[i0:i0 + len(w)] += w * r.uniform(0.6, 1.0)
    whips = fold_circular(whips, L)
    thorns = fine + coarse * 0.55 + snaps * 0.9 + whips * 0.4
    thorns = circ_reverb(thorns, r, decay=0.5, mix_db=-10.0, predelay=0.01, bright=5000.0)
    # tame the snap transients so the crackle sits as a dense, loud bed
    thorns = circ_compress(B.unit(thorns), -20.0, 4.0, win=0.004, smooth=0.006)

    ref = _k_rms(thorns)
    rel = dict(thorns=0.0, rumble=-1.5, hum=-3.0, swirl=-9.0, sing=-20.0)
    raw = dict(thorns=thorns, rumble=rum, hum=hum, swirl=swirl, sing=sing)
    layers = {k: raw[k] * (ref * 10 ** (g / 20) / _k_rms(raw[k])) for k, g in rel.items()}
    x = sum(layers.values())
    x = circ_filter(x, hp_mag(28, 2))
    x = circ_compress(B.unit(x), -14.0, 3.0, win=0.02, smooth=0.03)
    x = np.tanh(1.5 * B.unit(x)) / np.tanh(1.5)
    x = circ_filter(x, hp_mag(20, 1))  # no DC from the saturation
    return (layers, x) if debug else x


@recipe("storm_loop", loud=-13.0, src="synth", loop=True)
def storm_loop(c, v):
    """Briar storm wall, 10 s seamless loop: deep rolling rumble, dense thorny
    crackle (fine crackle waves, twig snaps, thorn scrapes, vine whips), an
    ominous beating, breathing drone (A1/Bb1 rub + Eb2 tritone) and swirling
    wind, glued with a seam-free compressor and gentle saturation. Every layer
    is built exactly periodic, so the loop point is sample-continuous."""
    return storm_layers(c.rng)


STORM_TICK_LOUD = -13.0
STORM_TICK_PEAK_DB = -1.6  # pre-encode peak; Vorbis overshoot on the click is a few tenths of a dB


def _peak_db(x):
    return 20 * np.log10(np.max(np.abs(x)) + 1e-12)


def _crest_guard(x, max_crest_db, hp=35.0):
    """Soft-saturate only the very top of the waveform so that peak minus the
    loudest 50 ms window (the build's loudness measure) is <= max_crest_db,
    measured as build_audio.finish() will see it (after its 35 Hz high-pass).
    With crest <= ceiling - loud the build's emergency tanh limiter stays idle,
    so the recipe -- not normalize() -- decides how the transient is shaped."""
    def crest(y):
        z = highpass(y, hp, 2)
        return _peak_db(z) - loudness_db(z)

    if crest(x) <= max_crest_db:
        return x
    pk = np.max(np.abs(x))

    def shape(d):
        return np.tanh(d * x / pk) / np.tanh(d) * pk

    lo, hi = 1e-3, 8.0
    for _ in range(24):  # bisection on the drive (deterministic)
        mid = 0.5 * (lo + hi)
        if crest(shape(mid)) > max_crest_db:
            lo = mid
        else:
            hi = mid
    return shape(hi)


@recipe("storm_damage_tick", variants=2, loud=STORM_TICK_LOUD, src="synth")
def storm_damage_tick(c, v):
    """Crisp clock tick played once per Briar damage second (storm.gd ticks
    every 1.0 s, so it is over in ~0.4 s), over a faint ominous undertone
    (A2 + Bb2 semitone rub, beating ~6.5 Hz, over an Eb3 tritone) and a short
    dark-room echo; a ghost of thorn prickle. Both takes are the SAME clock
    (take 2 only a touch lower/woodier, like the two pallets of one
    escapement), so a random pick never sounds like a second clock. The drop
    click is pre-shaped by a soft saturator so the peak stays under the -1 dBFS
    ceiling without the build's limiter touching it."""
    r = c.rng
    tick = B.clock_tick(r, f_scale=(1.0, 0.93)[v] * r.uniform(0.985, 1.015),
                        body_hz=(1150.0, 1050.0)[v] * r.uniform(0.98, 1.02),
                        case_amt=(0.9, 1.0)[v])
    tick = np.tanh(1.8 * tick) / np.tanh(1.8)  # round off the top of the drop click
    ref = loudness_db(tick)
    hall = reverb(tick, r, decay=0.4, mix_db=-17.0, predelay=0.018, bright=2600.0, tail=0.3)
    n = n_of(0.42)
    drone = (saw_bl(110.0, n, max_h=7) + 0.8 * saw_bl(116.54, n, max_h=7)
             + 0.5 * saw_bl(155.56, n, max_h=5) + 0.6 * np.sin(B.TAU * 55.0 * times(n)))
    drone = lowpass(drone, 520, 2) * env_pts(n, [(0, 0), (0.012, 1), (0.07, 0.7), (0.42, 0)]) ** 1.5
    drone *= 10 ** ((ref - 17.0 - loudness_db(drone)) / 20)
    prick = B.crackle(r, 0.06, 140, 2500, 7000)
    prick *= 10 ** ((ref - 27.0 - loudness_db(prick)) / 20)
    x = mix(0.45, (hall, 0, 0), (drone, 0.003, 0), (prick, 0.03, 0))
    # decoded peak must land <= -1.1 dBFS (the build normalises to STORM_TICK_LOUD)
    return _crest_guard(x, STORM_TICK_PEAK_DB - STORM_TICK_LOUD)


@recipe("ambient_forest_loop", loud=-24.0, src="synth", loop=True)
def ambient_forest_loop(c, v):
    r = c.rng
    L, X = 10.0, 1.0
    tot = L + X
    n = n_of(tot)
    swell = 0.6 + 0.4 * smooth_rand(n, r, 0.3, period=L)
    rust = np.clip(smooth_rand(n, r, 1.5, period=L), 0, 1) ** 2
    wind = B.unit(lowpass(colored(n, r, -3), 1100, 1)) * swell
    leaves = B.unit(bandpass(white(n, r), 3500, 0.8)) * rust
    beds = make_loop(mix(tot, (wind, 0, -6), (leaves, 0, -14)), L, X)

    ev = np.zeros(n_of(L + 2.5))

    def put(sig, t0, gain_db, far=False):
        if far:
            sig = lowpass(sig, 3500, 1)
        i0 = n_of(t0)
        ev[i0 : i0 + len(sig)] += sig * 10 ** (gain_db / 20)

    # crickets: chirp periods that divide the loop length exactly
    for k in range(16):
        put(B.cricket_chirp(4650), k * L / 16, -20)
    for k in range(12):
        put(B.cricket_chirp(5300, pulses=3), k * L / 12 + 0.21, -26, far=True)
    # birds
    put(B.bird_feebee(3900), 0.6, -3)
    put(B.bird_trill(r, 4300), 2.7, -9, far=True)
    put(B.bird_warble(r, 2900, 0.7), 4.3, -12, far=True)
    put(B.bird_chips(3300), 5.9, -6)
    put(B.dove_coo(520), 6.8, -10, far=True)
    put(B.bird_feebee(3600), 9.2, -12, far=True)
    ev = reverb(ev, r, decay=1.2, mix_db=-12)
    ev = fold_circular(ev, L)
    return beds + ev


# ==========================================================================
# UI / GAME FLOW
# ==========================================================================
@recipe("ui_click", variants=2, loud=-20.0, src="kenney")
def ui_click(c, v):
    return c.k("ui-audio", ["click2", "click4"][v])


UI_HOVER_GLISS = ((81, -9.0), (83, -7.0), (86, -4.5), (88, -2.5), (93, 0.0))  # A5 B5 D6 E6 A6 (pentatonic)


@recipe("ui_hover", loud=-26.0, src="synth")
def ui_hover(c, v):
    """Tiny, soft harp glissando swipe (A5-B5-D6-E6-A6, pentatonic, so it sits
    on any menu music): five plucked strings 17 ms apart, swelling into a
    ringing top A -- the only fast upward gliss in the game, so it reads as
    'hover' and never as a click, pickup or loot sound. Plucked at 0.31 of
    the string with light high-partial damping so the 2nd/3rd harmonics and
    the finger 'pluck' give it the gut-string character (not a sine bloop)."""
    r = c.rng
    total = 0.34
    gap = 0.017
    last = len(UI_HOVER_GLISS) - 1
    layers = []
    for i, (m, g) in enumerate(UI_HOVER_GLISS):
        t0 = gap * i + (r.uniform(-0.001, 0.001) if i else 0.0)  # human swipe, never < 15 ms apart
        layers.append((B.harp_note(midi_hz(m), total - t0, r, tau=0.22 if i == last else 0.11, pos=0.31,
                                   roll=2.0, damp=1.8, attack=0.0015, finger_db=-28.0, bloom=0.25), t0, g))
    x = mix(total, *layers)
    x = reverb(x, r, decay=0.22, mix_db=-17.0, predelay=0.008, bright=6000.0, tail=0.0)
    x = lowpass(x, 10000, 1)  # soft fingertips: no glassy top, but the string overtones stay
    return fade(pad_to(x, n_of(total)), 0.0, 0.1)


@recipe("kill_confirm", loud=-13.0, src="synth")
def kill_confirm(c, v):
    r = c.rng
    ding = bell(midi_hz(88), 0.9, partials=((1, 1.0, 1.0), (2.0, 0.4, 0.6), (3.0, 0.2, 0.4), (5.4, 0.08, 0.2)), tau=0.25)
    spark = bell(midi_hz(95), 0.6, tau=0.2)
    tick = B.crack(r, 0.0015, 5000)
    body = B.thump(330, 220, 0.02, 0.03, 0.12)
    return mix(1.5, (ding, 0, 0), (spark, 0.02, -10), (tick, 0, -14), (body, 0, -14))


@recipe("match_countdown_beep", loud=-16.0, src="synth")
def match_countdown_beep(c, v):
    n = n_of(0.18)
    x = additive(880.0, n, [(1, 1.0), (3, 0.22), (5, 0.08)])
    return x * env_pts(n, [(0, 0), (0.003, 1), (0.13, 0.7), (0.18, 0)])


@recipe("match_countdown_go", loud=-14.0, src="synth")
def match_countdown_go(c, v):
    n = n_of(0.6)
    x = additive(1760.0, n, [(1, 1.0), (3, 0.2)]) + 0.6 * additive(1318.5, n, [(1, 1.0), (3, 0.2)])
    x = x * env_pts(n, [(0, 0), (0.004, 1), (0.25, 0.8), (0.6, 0)])
    return mix(0.6, (x, 0, 0), (bell(midi_hz(93), 0.6, tau=0.3), 0, -6))


# --------------------------------------------------------------------------
# victory_fanfare: a synthesized rock sting written INTO the victory track.
# game.gd starts the music (fading in from -30 dB over 1.5 s, no loop) and the
# sting at the same instant, so the sting is in the track's key (D) and tuning
# and locked to its beat grid (measured on the official mp3), with the big
# chord on the track's bar-2 downbeat. game.gd must play it with
# pitch_jitter 0 for the lock to hold (the default 0.05 detunes it by up to
# +-89 cents and moves the hit by up to +-85 ms).
# --------------------------------------------------------------------------
TRACK_BPM = 173.95
BEAT = 60.0 / TRACK_BPM     # 0.3449 s
TRACK_T0 = 0.306            # the track's first downbeat (s from file start)
SIXTEENTH = BEAT / 4


def tb(beat):
    """Time (s) of a beat number on the track's grid (beat 0 = bar 1, beat 1)."""
    return TRACK_T0 + beat * BEAT


def _env_follow(x, att, rel, step=32):
    """Peak envelope with attack/release (s), computed on a decimated grid."""
    a = np.abs(x)
    nb = int(np.ceil(len(a) / step))
    a = np.pad(a, (0, nb * step - len(a))).reshape(nb, step).max(axis=1)
    ca = np.exp(-step / (att * 44100))
    cr = np.exp(-step / (rel * 44100))
    e = np.zeros(nb)
    v = 0.0
    for i in range(nb):
        c = ca if a[i] > v else cr
        v = c * v + (1 - c) * a[i]
        e[i] = v
    return np.interp(np.arange(len(x)) / step, np.arange(nb), e)


def _bus_compress(x, thr_db, ratio, att=0.004, rel=0.09, knee_db=6.0):
    env = 20 * np.log10(_env_follow(x, att, rel) + 1e-9)
    over = env - thr_db
    gr = np.where(over <= -knee_db / 2, 0.0,
                  np.where(over >= knee_db / 2, over * (1 - 1 / ratio),
                           (1 - 1 / ratio) * (over + knee_db / 2) ** 2 / (2 * knee_db)))
    return x * db(-gr)


def _sting_limit(x, ceiling, look=0.0015, rel=0.06):
    """Look-ahead brick-wall limiter: no sample above `ceiling` (linear)."""
    w = max(2, n_of(look))
    need = np.minimum(1.0, ceiling / (np.abs(x) + 1e-12))
    # running minimum over the look-ahead window (gain must already be down at the peak)
    g = need.copy()
    for k in range(1, w):
        g[:-k] = np.minimum(g[:-k], need[k:])
    # release: one-pole on a decimated grid (attack is instant thanks to the look-ahead)
    step = 16
    nb = int(np.ceil(len(g) / step))
    gb = np.pad(g, (0, nb * step - len(g)), constant_values=1.0).reshape(nb, step).min(axis=1)
    cr = np.exp(-step / (rel * 44100))
    out = np.empty(nb)
    v = 1.0
    for i in range(nb):
        v = gb[i] if gb[i] < v else cr * v + (1 - cr) * gb[i]
        out[i] = v
    gs = np.minimum(g, np.interp(np.arange(len(x)) / step, np.arange(nb), out))
    # smooth the gain curve (moving average over the look-ahead) to avoid crackle
    k = np.ones(w) / w
    gs = np.minimum(gs, np.convolve(gs, k, mode="same"))
    return x * gs


# --------------------------------------------------------------------------
# drum kit (synthesized)
# --------------------------------------------------------------------------
def _kick(r):
    n = n_of(0.5)
    body = B.thump(150, 50, 0.03, 0.12, 0.5, partial2=0.18)
    sub = sine(glide(n, 70, 48, 0.06), n) * env_exp(n, 0.004, 0.11)
    beater = B.unit(bandpass(white(n_of(0.03), r), 3200, 1.3)) * env_exp(n_of(0.03), 0.0002, 0.004)
    knock = B.unit(bandpass(white(n_of(0.06), r), 900, 2.0)) * env_exp(n_of(0.06), 0.0005, 0.012)
    x = mix(0.5, (body, 0, 0), (sub, 0, -6), (beater, 0, -10), (knock, 0, -14))
    return saturate(x, 1.8)


def _snare(r, tone=1.0):
    n = n_of(0.45)
    body = additive(glide(n, 250 * tone, 188 * tone, 0.02), n, [(1, 1.0), (1.59, 0.45), (2.14, 0.2)])
    body *= env_exp(n, 0.0008, 0.055)
    wires = highpass(bandpass(white(n, r), 5200, 0.55), 1700, 2)
    wires = B.unit(wires) * (0.65 * env_exp(n, 0.0006, 0.16) + 0.35 * env_exp(n, 0.0004, 0.035))
    crk = B.crack(r, 0.0025, 2600)
    x = mix(0.45, (body, 0, -3), (wires, 0, 0), (crk, 0, -7))
    return saturate(x, 1.5)


def _tom(r, f):
    n = n_of(0.7)
    body = additive(glide(n, f * 1.45, f, 0.035), n, [(1, 1.0), (1.5, 0.22), (2.0, 0.08)])
    body *= env_exp(n, 0.001, 0.26)
    stick = B.unit(bandpass(white(n_of(0.04), r), 2500, 1.0)) * env_exp(n_of(0.04), 0.0002, 0.006)
    return saturate(mix(0.7, (body, 0, 0), (stick, 0, -12)), 1.6)


def _metal(r, n, fmin, fmax, count, tau, tau_spread=(0.5, 1.4)):
    """Inharmonic partial cloud (cymbal shimmer), random but seeded."""
    t = times(n)
    out = np.zeros(n)
    for f in np.geomspace(fmin, fmax, count) * r.uniform(0.92, 1.08, count):
        a = (1000.0 / f) ** 0.25 * r.uniform(0.5, 1.0)
        ta = tau * r.uniform(*tau_spread)
        out += a * np.sin(2 * np.pi * f * t + r.uniform(0, 2 * np.pi)) * np.exp(-t / ta)
    return out


def _crash(r, dur=2.6, tau=0.85):
    n = n_of(dur)
    nz = highpass(white(n, r), 2800, 2)
    nz = peak_eq(nz, 6000, 5, q=0.6)
    nz = B.unit(lowpass(nz, 14000, 2))
    env = 0.55 * env_exp(n, 0.0015, tau) + 0.45 * env_exp(n, 0.0008, 0.09)
    shimmer = B.unit(highpass(_metal(r, n, 450, 11000, 70, tau * 0.9), 1800, 2))
    shimmer = shimmer * env_exp(n, 0.003, tau * 1.1)
    x = mix(dur, (nz * env, 0, 0), (shimmer, 0, -7), (B.crack(r, 0.002, 3500), 0, -8))
    return x


def _hat(r, open_=False):
    dur = 0.35 if open_ else 0.09
    n = n_of(dur)
    nz = B.unit(highpass(white(n, r), 7000, 3))
    met = B.unit(highpass(_metal(r, n, 3000, 13000, 24, 0.2), 6000, 2))
    tau = 0.11 if open_ else 0.018
    return (0.7 * nz + 0.5 * met) * env_exp(n, 0.0004, tau)


# --------------------------------------------------------------------------
# distorted electric guitar: Karplus-Strong strings -> amp -> cab
# --------------------------------------------------------------------------
def _ks(freq, dur, r, decay=0.9993, s=0.32, pick=0.17, bright=0.85, glide_c=6.0):
    """Karplus-Strong string, exactly in tune (fractional period fixed by varispeed).
    s < 0.5 = a lighter loop low-pass (brighter, longer-ringing electric string);
    `pick` puts the pick/pickup comb notch at that fraction of the string."""
    P = int(np.floor(SR / freq - s))
    f_act = SR / (P + s)
    n = n_of(dur * f_act / freq + 0.05)
    buf = r.uniform(-1, 1, P)
    buf = lowpass(buf, 1500 + 9500 * bright, 1)
    k = max(1, int(round(pick * P)))
    buf = buf - np.roll(buf, k)
    out = np.zeros(n + P + 1)
    out[:P] = buf
    i = P + 1
    out[P] = decay * ((1 - s) * out[0])
    while i < len(out):
        j = min(i + P, len(out))
        a = out[i - P : j - P]
        b = out[i - P - 1 : j - P - 1]
        out[i:j] = decay * ((1 - s) * a + s * b)
        i = j
    m = n_of(dur)
    ratio = (freq / f_act) * (1 + (2 ** (glide_c / 1200) - 1) * np.exp(-np.arange(m) / (0.035 * SR)))
    y = varispeed(out, ratio)[:m]
    return B.unit(y - np.mean(y))


def _amp(di, drive=14.0, gate=None):
    """High-gain amp + 4x12 cab: tight low end, mid push into two clip stages,
    scooped low mids, presence bump, steep speaker roll-off."""
    x = highpass(di, 120, 2)
    x = peak_eq(x, 760, 10, q=0.8)
    x = lowpass(x, 6000, 1)

    def stages(u):
        u = np.tanh(drive * u + 0.18) - np.tanh(0.18)  # asymmetric preamp (even harmonics)
        u = u - np.mean(u)
        u = np.tanh(2.6 * u)                            # power-amp squash
        return u

    x = shape_oversampled(x, stages, 4)
    if gate is not None:
        x = x * gate
    x = highpass(x, 80, 2)
    x = peak_eq(x, 115, 3.5, q=1.1)    # cab thump
    x = peak_eq(x, 380, -4.5, q=1.0)   # scoop mud
    x = peak_eq(x, 2300, 4.0, q=1.3)   # pick bite / presence
    x = peak_eq(x, 3900, -3.0, q=2.0)  # tame fizz
    x = lowpass(x, 5200, 4)            # speaker roll-off
    return B.unit(x)


DROP_D = {"D5": (38, 45, 50), "G5": (43, 50, 55), "A5": (45, 52, 57), "C5": (48, 55, 60),
          "D5big": (38, 45, 50, 57, 62)}


def _guitar_di(r, events, length, detune_c=0.0, shift=0.0):
    """Render a DI guitar part. events: (t, chord, kind, gain_db); kind 'open' rings
    until the next event (a real player mutes the old chord), 'mute' = palm mute,
    chord None = a choke (the previous chord is damped there and nothing new is played)."""
    out = np.zeros(n_of(length))
    gate = np.ones(n_of(length))
    for i, (t, chord, kind, g) in enumerate(events):
        if chord is None:
            continue
        t = t + shift
        nxt = events[i + 1][0] + shift if i + 1 < len(events) else length
        dur = max(0.05, nxt - t) + 0.02
        if kind == "mute":
            a, b = n_of(t), min(len(gate), n_of(nxt))
            gate[a:b] = 0.2 + 0.8 * np.exp(-np.arange(b - a) / (0.05 * SR))
            # 2 ms ramp back up into the next pick attack
            k = min(n_of(0.002), b - a)
            gate[b - k : b] = np.linspace(gate[b - k], 1.0, k)
        stroke = 0.0024 if kind == "mute" else 0.0065    # downstroke: low string first
        for k, m in enumerate(DROP_D[chord]):
            f = midi_hz(m) * 2 ** ((detune_c + r.uniform(-1.5, 1.5)) / 1200)
            if kind == "mute":
                s = _ks(f, min(dur, 0.2), r, decay=0.985, s=0.5, pick=0.13, bright=0.35)
                s *= env_exp(len(s), 0.0008, 0.05)
            else:
                s = _ks(f, dur, r, decay=0.9993, s=0.3, pick=0.17, bright=0.9)
            # release into the next chord (string damped by the fretting hand)
            rel = min(n_of(0.018), len(s) // 3)
            s[-rel:] *= np.linspace(1, 0, rel)
            i0 = n_of(t + k * stroke)
            seg = s[: max(0, len(out) - i0)]
            out[i0 : i0 + len(seg)] += seg * db(g - 2.0 * (k > 2))
    return out, gate


def _pick_scrape(r, dur):
    """'Shhhrrreeow' pick slide down the wound strings, rising into the downbeat."""
    n = n_of(dur)
    tt = times(n)

    def gain(tf, f):
        fc = 3800 * (650 / 3800) ** np.clip(tf / dur, 0, 1)
        g = 1 / np.sqrt(1 + 4.0 * (f / fc - fc / np.maximum(f, 1)) ** 2)
        return g
    nz = stft_filter(white(n, r), gain, win=1024, hop=256)
    # winding ridges: fast amplitude ripple whose rate falls with the slide
    rate = 900 * (180 / 900) ** (tt / dur)
    ripple = 0.6 + 0.4 * np.sin(phase_of(rate))
    return B.unit(nz * ripple) * env_pts(n, [(0, 0), (0.03, 0.35), (dur * 0.8, 1.0), (dur, 0.6)])


def _bass(r, events, length):
    """Picked electric bass doubling the guitar roots; m None = a rest (string damped)."""
    out = np.zeros(n_of(length))
    for i, (t, m, g) in enumerate(events):
        if m is None:
            continue
        nxt = events[i + 1][0] if i + 1 < len(events) else length
        dur = max(0.06, nxt - t)
        n = n_of(dur)
        f = midi_hz(m)
        x = saw_bl(f, n, max_h=30) * 0.6 + sine(f, n) * 0.8
        x = lowpass(x, 1100, 2)
        x *= env_pts(n, [(0, 0), (0.003, 1), (min(dur, 0.12), 0.75), (max(0.004, dur - 0.015), 0.6),
                         (dur, 0)])
        i0 = n_of(t)
        seg = x[: max(0, len(out) - i0)]
        out[i0 : i0 + len(seg)] += seg * db(g)
    return saturate(B.unit(out), 1.6)


# --------------------------------------------------------------------------
# tin whistle in D (woodland flourish)
# --------------------------------------------------------------------------
def _tin_whistle(r, notes, length):
    """notes: [(t, midi, dur)]; legato tin whistle with breath, chiff, delayed vibrato."""
    n = n_of(length)
    tt = times(n)
    # continuous pitch track (legato) built note by note
    pitch = np.full(n, np.nan)
    amp = np.zeros(n)
    for t, m, d in notes:
        a, b = n_of(t), min(n, n_of(t + d))
        pitch[a:b] = midi_hz(m)
        amp[a:b] = 1.0
        amp[a : a + n_of(0.006)] = 0.45   # tongued re-attack
    first = n_of(notes[0][0])
    pitch[:first] = midi_hz(notes[0][1])
    last = n_of(notes[-1][0] + notes[-1][2])
    pitch[last:] = midi_hz(notes[-1][1])
    pitch = np.where(np.isnan(pitch), np.interp(tt, tt[~np.isnan(pitch)], pitch[~np.isnan(pitch)]),
                     pitch)
    # quick finger glides between notes (~6 ms)
    k = n_of(0.006)
    lp = np.convolve(np.log(pitch), np.ones(k) / k, mode="same")
    lp[:k] = np.log(pitch[:k])
    lp[-k:] = np.log(pitch[-k:])
    f = np.exp(lp)
    # vibrato on the long last note only, fading in
    t_last = notes[-1][0]
    vd = np.clip((tt - t_last - 0.12) / 0.25, 0, 1) * 0.0085
    f = f * (1 + vd * np.sin(2 * np.pi * 5.6 * tt))
    # a real tin whistle is reedy, not a sine: strong 2nd/3rd harmonics + audible breath
    tone = additive(f, n, [(1, 1.0), (2, 0.36), (3, 0.17), (4, 0.065), (5, 0.03), (6, 0.012)])
    breath = B.unit(bandpass(white(n, r), 2600, 0.6)) * 0.15
    breath += B.unit(bandpass(white(n, r), 1300, 2.5)) * 0.08
    breath += B.unit(bandpass(white(n, r), 6000, 0.9)) * 0.06
    # amplitude: tongued attacks on each note, smoothed
    env = np.convolve(amp, np.ones(n_of(0.008)) / n_of(0.008), mode="same")
    chiff = np.zeros(n)
    for t, m, d in notes:
        a = n_of(t)
        L = n_of(0.03)
        if a + L < n:
            chiff[a : a + L] += env_exp(L, 0.0006, 0.007)
    x = (tone + breath) * env + B.unit(highpass(white(n, r), 3000, 2)) * chiff * 0.12
    return x


# --------------------------------------------------------------------------
# the sting
# --------------------------------------------------------------------------
FANFARE_LOUD = -8.5  # recipe loudness target (loudest 50 ms, K-weighted) = the big hit
# mix levels (dB): bar 1 sits under the hit so the hit is the payoff
G_GROOVE, G_FILL, G_RIFF, G_DRUMS, G_WHISTLE = -2.0, -8.0, -2.5, 3.0, -8.0
HIT_DRIVE = 2.0
G_PICKUP = -2.5


def _end_env(n, t0, t1):
    """1 until t0, raised-cosine fade to 0 at t1, 0 after."""
    u = np.clip((times(n) - t0) / (t1 - t0), 0, 1)
    return 0.5 * (1 + np.cos(np.pi * u))


@recipe("victory_fanfare", variants=1, loud=FANFARE_LOUD, src="synth")
def victory_fanfare(c, v):
    """Rock 'ultimate win' sting in D, locked to the victory track's grid:
    snare pickup -> 1 bar of power-chord riff over a rock beat -> the band stops dead
    while a tom fill + reverse cymbal suck into a huge low D5 + crash on the track's
    bar-2 downbeat (the loudest moment), the chord held to the end with a tin-whistle
    run on top."""
    return _fanfare(c.rng)


def _fanfare(r, stems=None):
    """The whole sting; `stems` (a dict) receives each bus at its mix level (debugging)."""
    L = 3.0
    HIT = tb(4)                 # 1.686 s: the big chord (track's bar 2, beat 1)
    STOP = tb(3.5)              # 1.513 s: guitar, bass and hats choke; only toms + swell lead in
    HOLD, END = 2.6, 2.95       # the chord rings at full level to HOLD, then everything fades
    n = n_of(L)
    out_env = _end_env(n, HOLD, END)

    # ---------------- drums ----------------
    kick, snare = _kick(r), _snare(r)
    # pickup: three 16th snares crescendo into the downbeat (own bus: the groove
    # compressor would flatten the crescendo)
    pickup = B.unit(mix(L, *[(_snare(r, 1.04), TRACK_T0 - (3 - i) * SIXTEENTH, g)
                             for i, g in enumerate((-9, -5, 0))]))
    groove = []
    # bar 1 rock beat: kick 1, 3, 3&; snare 2, 4; closed hats on 8ths (last one on beat 4)
    for b in (0, 2, 2.5):
        groove.append((kick, tb(b), 0 if b != 2.5 else -3))
    for b in (1, 3):
        groove.append((snare, tb(b), 0))
    for e in range(1, 7):
        groove.append((_hat(r), tb(e / 2), -15 if e % 2 else -12))
    groove = B.unit(_bus_compress(mix(L, *groove), -16, 3.0, att=0.006, rel=0.07))
    # the stop: high tom, low tom on the last two 16ths of the bar
    fill = B.unit(mix(L, (_tom(r, 196), STOP, -1), (_tom(r, 131), tb(3.75), 0)))
    # the hit: kick + floor tom + snare together, NOT squashed by the groove compressor
    hit_dr = B.unit(mix(L, (kick, HIT, 0), (_tom(r, 87), HIT, -9), (_snare(r, 0.97), HIT, -3)))
    if HIT_DRIVE:
        hit_dr = saturate(hit_dr, HIT_DRIVE)     # harder, denser hit (lower crest = more level)
    drum_bus = mix(L, (pickup, 0, G_PICKUP), (groove, 0, G_GROOVE), (fill, 0, G_FILL), (hit_dr, 0, 0))
    drum_bus = reverb(drum_bus, r, decay=0.55, mix_db=-13, predelay=0.008, bright=6500, tail=0.0)[:n]

    crash1 = _crash(r, 1.2, 0.45)                       # bar-1 accent, smaller than the hit
    crash2 = _crash(r, L - HIT, 0.8)                    # the hit crash (rings into the end fade)
    swell = _crash(r, BEAT * 1.4, 0.22)[::-1]           # reverse cymbal sucking into the hit
    swell *= env_pts(len(swell), [(0, 0), (BEAT * 0.9, 0.5), (BEAT * 1.4, 1.0)])
    cym = [(crash1, TRACK_T0, -9), (crash2, HIT, 0), (swell, HIT - BEAT * 1.4, -8)]
    cym_bus = reverb(mix(L, *cym), r, decay=1.0, mix_db=-16, tail=0.0)[:n]
    # cymbals + their room die a little earlier than the chord (no HF cut-off at the end)
    cym_bus *= _end_env(n, HOLD - 0.15, END - 0.05)

    # ---------------- guitars ----------------
    riff = [
        (tb(0), "D5", "open", 0),       # DAAA
        (tb(0.5), "D5", "mute", -9),    # chug
        (tb(1), "D5", "mute", -8),      # chug
        (tb(1.5), "D5", "mute", -9),    # chug
        (tb(2), "G5", "open", -1),      # climb G5
        (tb(2.5), "A5", "open", -1),    # A5
        (tb(3), "C5", "open", 0),       # C5 (mixolydian bVII) ...
        (STOP, None, "choke", 0),       # ... choked: the band stops dead for the fill
    ]
    big = [(HIT, "D5big", "open", 0)]   # -> huge low D5, own amp pass so it can be louder

    def double(events):
        di_a, gate_a = _guitar_di(r, events, L, detune_c=-3.0, shift=0.0)
        di_b, gate_b = _guitar_di(r, events, L, detune_c=+3.0, shift=0.004)
        return _amp(di_a * 0.45, gate=gate_a) + _amp(di_b * 0.45, gate=gate_b)

    riff_g = double(riff)
    big_g = double(big)
    # pick scrape through a lower-gain channel, swelling into the downbeat
    scrape = _amp(_pick_scrape(r, TRACK_T0 + 0.01) * 0.3, drive=5.0)
    scrape *= env_pts(len(scrape), [(0, 0.1), (TRACK_T0 * 0.85, 1.0), (TRACK_T0 + 0.01, 0.6)])
    # the held chord blooms and sings (finger vibrato)
    tt = times(n)
    vib = 1 + 0.0028 * np.clip((tt - HIT - 0.45) / 0.3, 0, 1) * np.sin(2 * np.pi * 5.2 * (tt - HIT))
    held = varispeed(big_g[n_of(HIT):], vib[n_of(HIT):])
    big_g = np.concatenate([big_g[: n_of(HIT)], held])[:n]
    big_g = np.pad(big_g, (0, max(0, n - len(big_g))))
    gtr = mix(L, (riff_g, 0, G_RIFF), (scrape, 0, G_RIFF - 9), (big_g, 0, 0))[:n]
    # make a little room for the whistle: dip the guitar's 1-2.5 kHz while it plays
    t_w = tb(5)

    def duck(tf, f):
        on = np.clip((tf - t_w + 0.05) / 0.08, 0, 1)
        return 1 - on * (1 - 10 ** (-2.5 / 20)) * np.exp(-0.5 * (np.log2(np.maximum(f, 1) / 1500) / 0.6) ** 2)
    gtr = stft_filter(gtr, duck, win=2048, hop=512)
    gtr = reverb(gtr, r, decay=0.8, mix_db=-17, predelay=0.015, bright=4500, tail=0.0)[:n] * out_env

    bass_riff = _bass(r, [(tb(0), 38, 0), (tb(0.5), 38, -3), (tb(1), 38, -2), (tb(1.5), 38, -3),
                          (tb(2), 43, -1), (tb(2.5), 45, -1), (tb(3), 48, 0), (STOP, None, 0)], L)
    bass_hit = _bass(r, [(HIT, 38, 0)], L)
    bass = mix(L, (bass_riff, 0, G_RIFF), (bass_hit, 0, 0))[:n] * out_env

    # ---------------- tin whistle ----------------
    w_notes = [(tb(5), 81, SIXTEENTH), (tb(5.25), 83, SIXTEENTH), (tb(5.5), 85, SIXTEENTH - 0.02),
               (tb(5.75) - 0.02, 91, 0.02),            # Celtic 'cut' (G6 flick) ...
               (tb(5.75), 86, END - tb(5.75))]         # ... onto a long high D6
    whis = _tin_whistle(r, w_notes, L)
    whis = reverb(whis, r, decay=1.2, mix_db=-9, predelay=0.02, bright=7000, tail=0.0)[:n] * out_env

    # ---------------- mix + master ----------------
    parts = {"gtr": (gtr, -3), "drums": (drum_bus, G_DRUMS), "cym": (cym_bus, -1), "bass": (bass, -9),
             "whistle": (whis, G_WHISTLE)}
    if stems is not None:
        for k, (sig, g) in parts.items():
            stems[k] = sig[:n] * db(g)
    x = mix(L, *[(sig, 0, g) for sig, g in parts.values()])[:n]
    if stems is not None:
        stems["premaster"] = x.copy()
    # no master bus compression: it squashed the hit back down to bar-1 level. The groove
    # is already compressed on its own bus and the amp/bass saturation keeps things dense.
    # Safety only: finish() puts the loudest 50 ms (K) at FANFARE_LOUD under a -1 dBFS
    # ceiling, so keep the peak 0.3 dB below that (one pass; iterating would chase the hit down).
    x = B.unit(x)
    x = _sting_limit(x, min(0.98, db(loudness_db(highpass(x, 35, 2)) + (-1.3 - FANFARE_LOUD))))
    x *= env_pts(len(x), [(0, 1), (L - 0.05, 1), (L, 0)])
    return x


@recipe("defeat_sting", loud=-14.0, src="kenney")
def defeat_sting(c, v):
    return c.k("music-jingles", "jingles_SAX07")  # descending "wah-wah-wah-waaah"
