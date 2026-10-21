"""Sound recipes: one function per manifest key.

Each recipe is registered with @recipe(key, variants, loud, src) and is called
once per variant as fn(c, v) -> mono numpy array, where `c` is the build
context (see build_audio.py):

    c.k(pack, stem, speed=1.0, start=0.0, dur=None)  -> Kenney CC0 clip,
        peak-normalised, optionally varispeed-resampled and sliced
    c.rng                                             -> seeded numpy Generator

`loud` is the target short-term (50 ms) RMS in dBFS used by the normaliser,
which gives the game a consistent starting mix (weapons loud, UI quiet).
`src` is "synth" (100 % original), "kenney" (processed Kenney only) or
"mixed" (Kenney layers + original synth layers); it drives the credits.
"""
import numpy as np

import blocks as B
from dsp import (SR, additive, bandpass, bell, bp_gain, colored, env_exp, env_pts,
                 fold_circular, highpass, lowpass, make_loop, midi_hz, mix, n_of,
                 pad_to, peak_eq, pluck, reverb, saturate, saw_bl, sine, smooth_rand,
                 stft_filter, times, varispeed, white)

RECIPES = []


def recipe(key, variants=1, loud=-14.0, src="mixed", loop=False):
    def deco(fn):
        RECIPES.append(dict(key=key, variants=variants, loud=loud, src=src, loop=loop, fn=fn))
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


@recipe("pistol_fire", variants=3, loud=-10.0)
def pistol_fire(c, v):
    """9 mm pistol: sharp snappy crack, slide clack, short outdoor tail."""
    r = c.rng
    rec = c.o(FF, FFP + "Walther PPQ/X_39P.wav")  # near perspective, 3 takes
    shot = take(rec, [1.41, 6.455, 10.68][v], 0.8, hold=0.06, tau=0.16)
    shot = peak_eq(shot, 3500, 2.5, q=0.8)  # a touch more snap
    crk = B.crack(r, 0.0022, 3800)
    punch = B.thump(120, 65, 0.02, 0.03, 0.2)
    slide = highpass(c.k("rpg-audio", "metalLatch", speed=1.35), 1500)
    crunch = highpass(c.k("impact-sounds", f"impactWood_light_00{v}", speed=1.4), 400)
    x = mix(0.7, (shot, 0, 0), (crk, PRE, -11), (punch, PRE, -15), (slide, PRE + 0.035, -21),
            (crunch, PRE + 0.004, -22))
    x = saturate(x, 1.3)
    return reverb(x, r, decay=0.55, mix_db=-17, tail=0.05)


@recipe("shotgun_fire", variants=3, loud=-8.5)
def shotgun_fire(c, v):
    """12-gauge pump: big boom, low-end punch, long rolling outdoor tail."""
    r = c.rng
    path, t = [("Nova/O_21P.wav", 0.43), ("Nova/O_21P.wav", 3.47), ("Model 12/K_22P.wav", 0.84)][v]
    shot = take(c.o(FF, FFP + path), t, 2.2, hold=0.3, tau=0.9)
    sub = B.thump(72, 40, 0.04, 0.12, 0.7)
    boom = B.lp_burst(r, 0.8, 180, 0.15, attack=0.002)
    crk = B.crack(r, 0.003, 3000)
    pellets = highpass(c.k("impact-sounds", f"impactWood_light_00{(v + 3) % 5}", speed=1.2), 400)
    x = mix(2.0, (shot, 0, 0), (sub, PRE, -8), (boom, PRE, -13), (crk, PRE, -12), (pellets, PRE + 0.005, -22))
    x = saturate(x, 1.4)
    x = _rolling_echoes(x, r, [(0.21, -14, 2000), (0.52, -18, 1300), (0.93, -23, 900)])
    return reverb(x, r, decay=1.8, mix_db=-13, tail=0.1)[: n_of(2.4)]


@recipe("shotgun_pump", variants=2, loud=-15.0, src="kenney")
def shotgun_pump(c, v):
    back = c.k("rpg-audio", "metalLatch", speed=0.8 + 0.06 * v)
    knock = c.k("impact-sounds", f"impactWood_light_00{v}", speed=1.3)
    fwd = c.k("rpg-audio", "metalLatch", speed=0.95 + 0.05 * v)
    slap = c.k("impact-sounds", f"impactPlank_medium_00{v + 2}", speed=1.4)
    return mix(0.55, (back, 0, 0), (knock, 0.004, -8), (fwd, 0.17 + 0.02 * v, -1), (slap, 0.172 + 0.02 * v, -10))


@recipe("lmg_fire", variants=4, loud=-11.0)
def lmg_fire(c, v):
    """LMG (7.62): heavier and chunkier, a little lower than the rifle, short per shot."""
    r = c.rng
    rec = c.o(FF, FFP + "AK-47/C_28P.wav")  # near perspective, 4 single takes
    shot = take(rec, [0.61, 3.26, 6.03, 9.175][v], 0.5, hold=0.05, tau=0.09)
    shot = varispeed(shot, [0.95, 0.93, 0.96, 0.94][v])
    shot = peak_eq(shot, 130, 4.0, q=0.9)  # chunkier low end
    crk = B.crack(r, 0.0025, 3200)
    body = B.thump(85, 50, 0.02, 0.04, 0.2)
    links = highpass(c.k("rpg-audio", "beltHandle1", speed=1.2), 1500)  # belt-feed rattle
    latch = highpass(c.k("rpg-audio", "metalLatch", dur=0.12, speed=1.1), 1200)
    crunch = highpass(c.k("impact-sounds", f"impactWood_light_00{v % 5}", speed=1.25), 400)
    x = mix(0.5, (shot, 0, 0), (crk, PRE, -11), (body, PRE, -10), (links, PRE + 0.05, -24),
            (latch, PRE + 0.04, -23), (crunch, PRE + 0.004, -22))
    x = saturate(x, 1.5)
    return reverb(x, r, decay=0.35, mix_db=-22, tail=0.03)[: n_of(0.5)]


@recipe("smg_fire", variants=4, loud=-12.0)
def smg_fire(c, v):
    """SMG: tight, light, rapid pops -- tail clamped so ~900 rpm stays crisp."""
    r = c.rng
    rec = c.o(FF, FFP + "PPSh/P_30P.wav")  # near perspective, single shots
    shot = take(rec, [0.97, 4.395, 8.26, 11.445][v], 0.3, hold=0.025, tau=0.045)
    shot = varispeed(shot, [1.0, 1.03, 0.98, 1.05][v])
    shot = highpass(shot, 90)  # lighter than the rifles
    crk = B.crack(r, 0.0018, 4200)
    crunch = highpass(c.k("impact-sounds", f"impactWood_light_00{(v + 1) % 5}", speed=1.7), 500)
    x = mix(0.3, (shot, 0, 0), (crk, PRE, -12), (crunch, PRE + 0.003, -23))
    x = saturate(x, 1.25)
    return reverb(x, r, decay=0.25, mix_db=-20, tail=0.0)


@recipe("rifle_fire", variants=3, loud=-10.0)
def rifle_fire(c, v):
    """Assault rifle (5.56): sharp crack + body thump, medium outdoor tail."""
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


@recipe("sniper_fire", variants=2, loud=-8.0)
def sniper_fire(c, v):
    """.30-06 bolt rifle: huge crack + deep boom + long rolling echo."""
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


@recipe("sniper_bolt", loud=-15.0, src="kenney")
def sniper_bolt(c, v):
    """Bolt cycle: lift - pull back - push forward - lock down (+ spent carrot stub)."""
    lift = c.k("rpg-audio", "metalClick", start=0.05, speed=1.1)
    back = c.k("rpg-audio", "metalLatch", speed=0.82)
    fwd = c.k("rpg-audio", "metalLatch", speed=1.0)
    lock = c.k("rpg-audio", "metalClick", start=0.05, speed=0.9)
    knock = c.k("impact-sounds", "impactWood_light_004", speed=1.3)
    stub = c.k("impact-sounds", "impactWood_light_002", speed=1.8)
    return mix(0.9, (lift, 0, -4), (back, 0.11, 0), (stub, 0.24, -16), (fwd, 0.33, -1),
               (lock, 0.47, -3), (knock, 0.47, -9))


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
    r = c.rng
    body = c.o("baradari-explosions", ["explosions/explode.wav", "explosions/explodemini.wav",
                                       "explosions/explode.wav"][v])
    body = varispeed(body, [1.0, 0.95, 0.9][v])
    crunch = c.k("sci-fi-sounds", f"explosionCrunch_00{[0, 1, 3][v]}")
    sub = lowpass(c.k("sci-fi-sounds", f"lowFrequency_explosion_00{[1, 0, 1][v]}"), 300)
    boom = B.lp_burst(r, 2.0, 200, 0.35, attack=0.004)
    kick = B.thump(85, 45, 0.08, 0.2, 1.0)
    poof = B.burst(r, 0.8, 600, 0.7, 0.15, attack=0.003)
    debris = B.grains(r, 2.0, 30, 300, 3000, glen=(0.01, 0.03), t_tau=0.35, start=0.12)
    clump1 = c.k("impact-sounds", f"footstep_grass_00{v}", speed=0.9)
    clump2 = c.k("impact-sounds", f"impactSoft_medium_00{v + 1}", speed=1.1)
    x = mix(2.2, (body, 0, 0), (crunch, 0, -5), (highpass(sub, 40), 0, -4), (boom, 0, -7), (kick, 0, -5),
            (poof, 0, -9), (debris, 0, -9), (clump1, 0.55 + 0.1 * v, -13), (clump2, 0.8, -15))
    x = saturate(highpass(x, 40, 2), 1.7)
    return reverb(x, r, decay=1.3, mix_db=-12, tail=0.3)[: n_of(2.6)]


@recipe("reload_start", loud=-16.0, src="kenney")
def reload_start(c, v):
    cloth = c.k("rpg-audio", "cloth2")
    click = c.k("rpg-audio", "metalClick", start=0.05)
    popout = c.k("impact-sounds", "impactWood_light_003", speed=1.4)
    return mix(0.6, (cloth, 0, -4), (click, 0.06, 0), (popout, 0.16, -5))


@recipe("reload_end", loud=-14.0, src="kenney")
def reload_end(c, v):
    slap = c.k("impact-sounds", "impactPlank_medium_001", speed=1.2)
    latch = c.k("rpg-audio", "metalLatch")
    click = c.k("rpg-audio", "metalClick", start=0.06, speed=1.15)
    return mix(0.5, (slap, 0, -2), (latch, 0.09, 0), (click, 0.2, -8))


@recipe("dry_fire", loud=-18.0)
def dry_fire(c, v):
    r = c.rng
    click = highpass(c.k("rpg-audio", "metalClick", start=0.05, dur=0.2, speed=1.25), 800)
    puff = B.burst(r, 0.08, 900, 0.8, 0.015, attack=0.002)
    return mix(0.25, (click, 0, 0), (puff, 0.004, -12))


@recipe("weapon_swap", variants=2, loud=-16.0, src="kenney")
def weapon_swap(c, v):
    cloth = c.k("rpg-audio", ["cloth3", "cloth1"][v])
    rattle = c.k("rpg-audio", "beltHandle1", speed=1.0 + 0.1 * v)
    latch = c.k("rpg-audio", "metalLatch", speed=1.0 - 0.05 * v)
    return mix(0.6, (cloth, 0, -4), (rattle, 0.05, -10), (latch, 0.2 + 0.05 * v, -1))


# ==========================================================================
# IMPACTS & GORE
# ==========================================================================
@recipe("carrot_impact_dirt", variants=3, loud=-13.0)
def carrot_impact_dirt(c, v):
    r = c.rng
    thud = c.k("impact-sounds", f"impactSoft_medium_00{v}")
    crunch = c.k("impact-sounds", f"footstep_grass_00{v + 1}", speed=1.15)
    spray = B.grains(r, 0.4, 25, 1500, 6000, t_tau=0.05)
    low = B.thump(110, 60, 0.02, 0.03, 0.15)
    return mix(0.4, (thud, 0, -4), (crunch, 0, 0), (spray, 0.005, -5), (low, 0, -10))


@recipe("carrot_impact_wood", variants=3, loud=-13.0)
def carrot_impact_wood(c, v):
    r = c.rng
    wood = c.k("impact-sounds", f"impactWood_medium_00{v}")
    plank = c.k("impact-sounds", f"impactPlank_medium_00{v + 1}", speed=1.1)
    thunk = B.thump(260, 170, 0.03, 0.04, 0.2, partial2=0.3)
    splint = B.grains(r, 0.3, 8, 3000, 7000, t_tau=0.04)
    return mix(0.45, (wood, 0, 0), (plank, 0, -5), (thunk, 0, -8), (splint, 0.003, -14))


@recipe("carrot_impact_flesh", variants=3, loud=-12.0)
def carrot_impact_flesh(c, v):
    r = c.rng
    punch = c.k("impact-sounds", f"impactPunch_medium_00{v}", speed=0.95)
    slime = c.k("sci-fi-sounds", "slime_000", speed=1.0 + 0.15 * v, dur=0.35)
    slime = slime * env_pts(len(slime), [(0, 1), (0.25, 0.6), (len(slime) / SR, 0)])
    wet = B.squelch(r, 0.16, [(0, 500), (0.05, 1800 - 200 * v), (0.16, 700)], q=3.0)
    low = B.thump(150, 80, 0.03, 0.05, 0.25)
    return mix(0.45, (punch, 0, 0), (slime, 0.005, -5), (wet, 0.004, -5), (low, 0, -6))


@recipe("headshot", variants=2, loud=-11.0)
def headshot(c, v):
    r = c.rng
    if v == 0:  # BONK! (+ little pop)
        knock = c.k("impact-sounds", "impactWood_light_001", speed=0.75)
        bk = B.bonk(r, 620, 380)
        pop = B.cork_pop(r, 320, 950)
        return mix(0.55, (bk, 0, 0), (knock, 0, -6), (pop, 0.005, -7))
    # POP! (+ softer bonk and a springy wobble)
    pop = B.cork_pop(r, 360, 1100, dur=0.16, noise_db=-4)
    bk = B.bonk(r, 700, 450, dur=0.3)
    spring = B.boing(300, dur=0.3, wobble=0.2, rate=30, rise=0.8)
    return mix(0.55, (pop, 0, 0), (bk, 0.004, -6), (spring, 0.05, -11))


@recipe("gore_splat", variants=3, loud=-11.0)
def gore_splat(c, v):
    r = c.rng
    meat = lowpass(c.k("impact-sounds", f"impactPunch_heavy_00{v}"), 2500)
    slime = c.k("sci-fi-sounds", "slime_000", speed=0.85 + 0.1 * v)
    drops = B.droplets(r, 0.8, 18, t_tau=0.12, start=0.04)
    wet = B.squelch(r, 0.28, [(0, 400), (0.06, 1500), (0.28, 600)], q=2.5)
    return mix(0.8, (meat, 0, -1), (slime, 0, -2), (drops, 0, -10), (wet, 0.003, -3))


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


@recipe("body_fall", variants=3, loud=-13.0)
def body_fall(c, v):
    r = c.rng
    thud = c.k("impact-sounds", f"impactSoft_heavy_00{v}")
    leaves = c.k("impact-sounds", f"footstep_grass_00{v + 1}")
    bounce = c.k("impact-sounds", f"impactSoft_medium_00{v + 2}", speed=1.05)
    rustle = B.burst(r, 0.4, 3000, 0.7, 0.1, attack=0.01)
    return mix(0.8, (thud, 0, 0), (leaves, 0, -4), (bounce, 0.17 + 0.03 * v, -9), (rustle, 0.02, -17))


# ==========================================================================
# MOVEMENT
# ==========================================================================
@recipe("footstep_grass", variants=5, loud=-20.0, src="kenney")
def footstep_grass(c, v):
    x = c.k("impact-sounds", f"footstep_grass_00{v}", speed=1.12, dur=0.3)
    return highpass(x, 100)


@recipe("hop", variants=3, loud=-20.0)
def hop(c, v):
    r = c.rng
    b = B.boing([170, 195, 220][v], dur=0.32)
    swish = B.whoosh(r, 0.2, 700, 2000, q=1.2, peak=0.35)
    pad = c.k("impact-sounds", f"impactSoft_medium_00{v}", speed=1.3)
    return mix(0.35, (b, 0, 0), (swish, 0, -10), (pad, 0, -14))


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


@recipe("glider_open", variants=2, loud=-14.0)
def glider_open(c, v):
    r = c.rng
    snap = c.k("rpg-audio", ["cloth1", "cloth2"][v])
    fwump = B.lp_burst(r, 0.5, 350, 0.12, attack=0.006)
    sw = B.whoosh(r, 0.5, 2000, 500, q=1.2, peak=0.15)
    n = n_of(0.4)
    flutter = B.unit(bandpass(white(n, r), 1200, 0.8)) * (0.5 + 0.5 * np.sin(2 * np.pi * 18 * times(n))) * env_exp(n, 0.01, 0.1)
    return mix(0.9, (snap, 0, -2), (fwump, 0.02, 0), (sw, 0, -6), (flutter, 0.05, -12))


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
    r = c.rng
    latch = c.k("rpg-audio", "metalLatch")
    cloth = c.k("rpg-audio", "cloth4")
    layers = [(latch, 0, 0), (cloth, 0, -6)]
    for i, m in enumerate([67, 74, 79]):  # G4 D5 G5 plucked
        layers.append((pluck(midi_hz(m), 0.35, r), 0.05 + 0.05 * i, -9))
    return mix(0.6, *layers)


@recipe("crate_open", loud=-13.0)
def crate_open(c, v):
    r = c.rng
    creak = c.k("rpg-audio", "creak3")
    lid = c.k("impact-sounds", "impactWood_medium_002", speed=0.9)
    layers = [(creak, 0, -2), (lid, 0.28, 0)]
    for i, m in enumerate([79, 83, 86, 91]):  # G5 B5 D6 G6 loot sparkle
        layers.append((bell(midi_hz(m), 0.7, tau=0.3), 0.3 + 0.045 * i, -8 - i))
    n = n_of(0.7)
    shimmer = B.unit(highpass(white(n, r), 6000)) * env_pts(n, [(0, 0), (0.1, 1), (0.7, 0)])
    layers.append((shimmer, 0.3, -24))
    return mix(1.2, *layers)


@recipe("armor_break", variants=2, loud=-11.0)
def armor_break(c, v):
    r = c.rng
    wood = c.k("impact-sounds", f"impactWood_heavy_00{v}")
    crunch = c.k("impact-sounds", f"impactMining_00{v + 2}", speed=1.2)
    crk = B.crack(r, 0.015, 2000)
    splinters = B.grains(r, 0.6, 30, 2000, 7000, t_tau=0.07)
    tink1 = bell(2100 + 150 * v, 0.2, tau=0.05)
    tink2 = bell(2600 - 100 * v, 0.2, tau=0.05)
    n = n_of(0.4)
    sad = sine(np.geomspace(520, 260, n), n) * env_pts(n, [(0, 0), (0.02, 1), (0.4, 0)])
    return mix(0.9, (wood, 0, 0), (crunch, 0, -4), (crk, 0, -6), (splinters, 0.002, -12),
               (tink1, 0.18, -15), (tink2, 0.31, -17), (sad, 0.1, -15))


# ==========================================================================
# CRITTER VOICES
# ==========================================================================
HURT = [
    # (dur, f0 contour, vowel morph, kwargs) -- "eek!", "yip", "ow!", "eep-eep", "squeee", "ngh!"
    (0.22, [(0, 1150), (0.04, 1600), (0.22, 1050)], [(0, "i"), (0.22, "e")], dict()),
    (0.12, [(0, 1400), (0.03, 1900), (0.12, 1500)], [(0, "i"), (0.12, "a")], dict(breath=0.05)),
    (0.28, [(0, 800), (0.05, 1050), (0.28, 650)], [(0, "a"), (0.28, "u")], dict(breath=0.15, scale=1.5)),
    None,  # eep-eep (two syllables, built below)
    (0.32, [(0, 1300), (0.06, 1750), (0.32, 1350)], [(0, "i"), (0.32, "i")],
     dict(rasp=0.4, vib=(14.0, 0.03, 0.03))),
    (0.22, [(0, 420), (0.05, 560), (0.22, 380)], [(0, "uh"), (0.22, "uh")],
     dict(rasp=0.3, breath=0.2, scale=1.2)),
]


@recipe("hurt_squeak", variants=6, loud=-14.0, src="synth")
def hurt_squeak(c, v):
    r = c.rng
    if HURT[v] is None:
        a = B.voice(r, 0.09, [(0, 1600), (0.02, 1750), (0.09, 1500)], [(0, "i"), (0.09, "i")])
        b = B.voice(r, 0.11, [(0, 1450), (0.02, 1650), (0.11, 1300)], [(0, "i"), (0.11, "e")])
        return mix(0.3, (a, 0, 0), (b, 0.13, -1))
    dur, f0, vow, kw = HURT[v]
    return B.voice(r, dur, f0, vow, **kw)


@recipe("death_squeak", variants=3, loud=-14.0, src="synth")
def death_squeak(c, v):
    r = c.rng
    if v == 0:  # long falling wail that runs out of breath
        w = B.voice(r, 1.0, [(0, 1300), (0.08, 1600), (0.5, 900), (1.0, 380)],
                    [(0, "i"), (0.5, "e"), (1.0, "u")], vib=(7.0, 0.01, 0.06), breath=0.12,
                    amp_pts=[(0, 0), (0.02, 1), (0.7, 0.7), (1.0, 0)])
        puff = B.burst(r, 0.25, 1200, 0.6, 0.06, attack=0.01)
        return mix(1.3, (w, 0, 0), (puff, 0.95, -14))
    if v == 1:  # "squeak... squeeeak" two falling squeaks
        a = B.voice(r, 0.25, [(0, 1400), (0.04, 1550), (0.25, 1000)], [(0, "i"), (0.25, "e")])
        b = B.voice(r, 0.45, [(0, 1150), (0.05, 1250), (0.45, 550)], [(0, "e"), (0.45, "u")],
                    vib=(6.0, 0.01, 0.05), rasp=0.2)
        return mix(0.9, (a, 0, 0), (b, 0.37, -1))
    # cartoon slide-whistle drop after a little "eep"
    eep = B.voice(r, 0.1, [(0, 1700), (0.03, 1900), (0.1, 1600)], [(0, "i"), (0.1, "i")])
    sw = B.slide_whistle([(0, 1900), (0.75, 330)], 0.8, rng=r)
    return mix(1.0, (eep, 0, 0), (sw, 0.12, -3))


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


@recipe("storm_loop", loud=-18.0, src="synth", loop=True)
def storm_loop(c, v):
    r = c.rng
    L, X = 8.0, 1.0
    tot = L + X
    n = n_of(tot)
    t = times(n)
    lfo = 0.5 + 0.5 * smooth_rand(n, r, 0.4, period=L)
    lfo2 = smooth_rand(n, r, 0.25, period=L)
    rumble = B.unit(highpass(lowpass(colored(n, r, -6), 120, 2), 40, 2)) * (0.6 + 0.4 * lfo)

    def g(tt, f):
        i = np.clip((tt[:, 0] * SR).astype(int), 0, n - 1)
        fc = (650 + 450 * lfo2[i])[:, None]
        return bp_gain(f, fc, 1.2)

    swirl = B.unit(stft_filter(colored(n, r, -3), g)) * (0.4 + 0.6 * lfo)
    hum = sum(saw_bl(f, n, max_h=12) for f in (55.0, 82.41, 110.3))
    hum = B.unit(lowpass(hum, 400, 2)) * (0.7 + 0.3 * np.sin(2 * np.pi * 4 * t))  # 4 Hz -> 32 cycles / loop
    beds = make_loop(mix(tot, (rumble, 0, -8), (swirl, 0, -3), (hum, 0, -14)), L, X)

    # thorn crackles + whip whooshes are events: render then wrap circularly
    events = B.crackle(r, L, 40, 1500, 6500, period=L)
    whips = np.zeros(n_of(L + 0.5))
    for t0 in (0.7, 2.3, 4.1, 5.6, 7.2):
        w = B.whoosh(r, 0.22, 3200, 800, q=1.6, peak=0.25)
        i0 = n_of(t0 + r.uniform(-0.2, 0.2))
        whips[i0 : i0 + len(w)] += w * r.uniform(0.6, 1.0)
    whips = fold_circular(whips, L)
    return beds + B.unit(events) * 10 ** (1 / 20) + whips * 10 ** (-7 / 20)


@recipe("storm_damage_tick", variants=2, loud=-14.0)
def storm_damage_tick(c, v):
    r = c.rng
    scratch = c.k("interface-sounds", ["scratch_001", "scratch_002"][v])
    prick = B.crack(r, 0.004, 4000)
    thud = B.thump(140, 70, 0.02, 0.03, 0.15)
    sizzle = B.crackle(r, 0.09, 110, 2000, 7000)
    return mix(0.3, (scratch, 0, -2), (prick, 0, -3), (thud, 0, -6), (sizzle, 0.01, -9))


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


@recipe("ui_hover", loud=-26.0, src="kenney")
def ui_hover(c, v):
    return c.k("ui-audio", "rollover2")


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


@recipe("victory_fanfare", loud=-12.0)
def victory_fanfare(c, v):
    r = c.rng
    pick = c.k("music-jingles", "jingles_PIZZI10")  # Kenney pizzicato run D4 E4 F#4 G4 (G major)
    layers = [(pick, 0, -2)]
    # "da - da - DAAA" in G major on top of the run
    for t0 in (0.43, 0.55):
        for m in (71, 74):  # B4 D5 staccato
            layers.append((pluck(midi_hz(m), 0.15, r, decay=0.99), t0, -6))
    T = 0.67
    for i, m in enumerate((55, 62, 67, 71, 74, 79)):  # G3 D4 G4 B4 D5 G5 strum
        layers.append((pluck(midi_hz(m), 1.8, r, decay=0.997), T + 0.015 * i, -7))
    n = n_of(2.2)
    pad = sum(saw_bl(midi_hz(m), n, max_h=20) for m in (55, 59, 62, 67))
    pad = lowpass(pad, 2200, 2) * env_pts(n, [(0, 0), (0.04, 1), (1.4, 0.8), (2.2, 0)])
    layers.append((B.unit(pad), T, -10))
    for i, m in enumerate((79, 83, 86, 91)):  # glockenspiel sparkle
        layers.append((bell(midi_hz(m), 1.2, tau=0.35), T + 0.06 * i, -9 - i))
    timp = B.thump(98, 92, 0.2, 0.45, 1.5, partial2=0.2)
    n2 = n_of(1.8)
    cym = B.unit(highpass(white(n2, r), 5000)) * env_exp(n2, 0.005, 0.6)
    layers += [(timp, T, -6), (cym, T, -18)]
    return reverb(mix(3.0, *layers), r, decay=1.1, mix_db=-14, tail=0.0)


@recipe("defeat_sting", loud=-14.0, src="kenney")
def defeat_sting(c, v):
    return c.k("music-jingles", "jingles_SAX07")  # descending "wah-wah-wah-waaah"
