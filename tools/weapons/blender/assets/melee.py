"""Melee clubs: every species pulls out its own bat when its paws are empty.

    melee_barbed_carrot     Bun           a carrot club, barbed wire round the business end
    melee_shadow_carrot     Bandit Bunny  a near-black carrot with violet veins and thorns
    melee_fly_swatter       Frog          a plastic swatter with a fly squashed through the mesh
    melee_bunny_spine       Fox           a bunny's spine with its head still on the end
    melee_acorn_knocker     Squirrel      a stick with a bloody acorn dangling off the end
    melee_mousetrap_mallet  Hamster       a pencil with a sprung mousetrap (and someone's tail)
    melee_nail_corncob      Raccoon       a gnawed corncob on a dowel, rusty nails driven through
    melee_trout_stick       Beaver        a gnawed branch with a trout skewered on the point

Builder space as for the guns (+Y forward, +Z up, metres), origin at the hand
grip, the striking end along +Y (exported as -Z, like a barrel). A swing
leads with the club's -Z side, so that is where the blood goes. Each club is
~0.4 m long; the game scales held weapons with the critter (about 1.1 m in a
2 m critter's paws).

Markers: `Tip` - the far end of the striking part.
"""
from __future__ import annotations

import math
import random

import bpy
from mathutils import Matrix, Vector

from bbd import geo, mats, parts, util

TAU = math.pi * 2.0


# --------------------------------------------------------------------------- shared bits

def M():
    return {
        "blood": mats.plain("blood", "#5a0606", rough=0.12, coat=0.8, noise_amt=0.25, noise_scale=60.0, bump=0.05),
        "blood_dry": mats.plain("blood_dry", "#3b0705", rough=0.45, noise_amt=0.35, noise_scale=90.0, bump=0.1),
        "steel": mats.metal("steel", "steel", wear=0.5),
        "rust": mats.metal("rust", "iron", tint="#7a4428", rough=0.85, wear=0.2),
        "brass": mats.metal("brass", "brass", wear=0.6),
        "leather": mats.leather("leather", tint="#5e3a22"),
        "twine": mats.fibre("twine"),
        "twine_wrap": mats.twine_wrap(),
        "bark": mats.bark("bark", tint="#cdb79c"),
        "pine": mats.wood("pine", "coated_pine", coords="src", tint="#e8c9a0", rough=0.5),
        "bone": mats.plain("bone", "#e8dcc0", rough=0.55, noise_amt=0.25, noise_scale=140.0, bump=0.25),
        "gristle": mats.plain("gristle", "#c9776a", rough=0.25, coat=0.5, noise_amt=0.3, noise_scale=80.0),
    }


def blob(name, pos, r, mat, normal=(0, 0, 1), squash=0.45, seed=0, rough=0.25):
    """A small irregular glob (blood, guts), flattened along `normal`."""
    prof = [(r * math.cos(a), r * math.sin(a)) for a in [math.pi * (1 - k / 6) for k in range(7)]]
    prof[0] = (-r, 0.0)
    prof[-1] = (r, 0.0)
    obj = geo.lathe(name, prof, segs=10, mat=mat, sharp_angle=None)
    geo.displace_noise(obj, r * rough, 1.2 / r, seed)
    obj.scale = (1.0, squash, 1.0)
    return parts.orient(obj, normal, pos)


def drip(name, start, length, r, mat, direction=(0, 0, -1), seed=0):
    """A run of blood that ends in a hanging drop."""
    rng = random.Random(seed)
    d = Vector(direction).normalized()
    side = d.orthogonal().normalized()
    pts, radii = [], []
    for k in range(6):
        q = k / 5
        pts.append(Vector(start) + d * length * q + side * rng.uniform(-0.15, 0.15) * r * q)
        radii.append(r * (1.0 - 0.45 * q) if k < 4 else (r * 1.15 if k == 4 else r * 0.25))
    return geo.sweep(name, pts, radii, segs=6, mat=mat, caps=True)


def splatter(name, centre, axis, radius, n, mat, seed=0, size=0.006, drips=0, drip_len=0.02):
    """Blood dabbed on a roughly cylindrical surface: `n` globs around `axis`
    at `radius` (biased to the -Z side, which leads every swing), plus drips."""
    rng = random.Random(seed)
    c, ax = Vector(centre), Vector(axis).normalized()
    u = Vector((0, 0, -1)) - ax * Vector((0, 0, -1)).dot(ax)
    u = u.normalized() if u.length > 1e-6 else ax.orthogonal().normalized()
    v = ax.cross(u)
    out = []
    for k in range(n):
        a = rng.gauss(0.0, 0.9)
        along = rng.uniform(-1.0, 1.0) * radius * 1.4
        nrm = u * math.cos(a) + v * math.sin(a)
        p = c + ax * along + nrm * radius
        out.append(blob(f"{name}_{k}", p, size * rng.uniform(0.6, 1.3), mat, nrm, 0.35, seed + k))
        if k < drips:
            out.append(drip(f"{name}_drip{k}", p, drip_len * rng.uniform(0.6, 1.2), size * 0.35, mat,
                            seed=seed + 50 + k))
    return out


def wrap(name, radius_at, y0, y1, mat, extra=0.0022, n=10, segs=18):
    """A sleeve (leather / twine wrap) hugging a handle whose radius varies along Y."""
    prof = [(y0, radius_at(y0) + extra * 0.2)]
    for k in range(n + 1):
        y = y0 + (y1 - y0) * k / n
        prof.append((y, radius_at(y) + extra))
    prof.append((y1, radius_at(y1) + extra * 0.2))
    obj = geo.lathe(name, prof, segs=segs, mat=mat, cap0=False, cap1=False, sharp_angle=None)
    obj["bbd_uv"] = "src"
    return obj


def carrot_radius(prof, t):
    """Radius of a geo.carrot_profile at distance t from the tip."""
    for (t0, r0), (t1, r1) in zip(prof, prof[1:]):
        if t0 <= t <= t1:
            return r0 + (r1 - r0) * (t - t0) / max(t1 - t0, 1e-9)
    return prof[-1][1] if t > prof[-1][0] else prof[0][1]


def wobbly_stick(name, y0, y1, r0, r1, mat, seed=0, n=9, wiggle=0.006):
    """A natural stick along Y: wanders a little, thickens toward the far end."""
    rng = random.Random(seed)
    pts, radii = [], []
    for k in range(n):
        q = k / (n - 1)
        w = wiggle * math.sin(q * math.pi) if 0 < k < n - 1 else 0.0
        pts.append(Vector((rng.uniform(-1, 1) * w, y0 + (y1 - y0) * q, rng.uniform(-1, 1) * w)))
        radii.append((r0 + (r1 - r0) * q) * rng.uniform(0.95, 1.05))
    obj = geo.sweep(name, pts, radii, segs=12, mat=mat, caps=True)
    geo.displace_noise(obj, r0 * 0.08, 60.0, seed)
    return obj, pts, radii


def twig(name, base, direction, length, r, mat, seed=0):
    d = Vector(direction).normalized()
    rng = random.Random(seed)
    pts = [Vector(base) + d * length * q + Vector((0, 0, rng.uniform(-0.1, 0.1) * length * q)) for q in (0, 0.5, 1)]
    return geo.sweep(name, pts, [r, r * 0.75, r * 0.45], segs=6, mat=mat, caps=True)


def smooth3(pts, iters=2):
    """Open-curve corner cutting in 3-D (geo.chaikin works on 2-D outlines)."""
    P = [Vector(p) for p in pts]
    for _ in range(iters):
        out = [P[0]]
        for a, b in zip(P, P[1:]):
            out += [a.lerp(b, 0.25), a.lerp(b, 0.75)]
        out.append(P[-1])
        P = out
    return P


def scale_about(objs, pivot, s):
    """Grow a finished group of parts by `s` about `pivot` (freezes transforms)."""
    bpy.context.view_layer.update()
    m = Matrix.Translation(Vector(pivot)) @ Matrix.Scale(s, 4) @ Matrix.Translation(-Vector(pivot))
    for o in objs:
        util.apply_transform(o)
        o.data.transform(m)
        o.data.update()
    return objs


def custom(name, build):
    """Get-or-create a node material through mats.NB; `build(nb)` fills it in."""
    mat, nb = mats._new(name)
    if nb is not None:
        build(nb)
    return mat


def report(notes):
    return {"notes": "Origin at the hand grip, striking end along -Z (Godot). " + notes}


# --------------------------------------------------------------------------- Bun: barbed-wire carrot

def _carrot_club(name, L, R, y_tip, cut, seed, power=1.15):
    """A big carrot held by its tapering tip; returns (obj, radius_at(y), crown y)."""
    obj = parts.carrot_part(name, L, R, pos=(0, y_tip, 0), axis=(0, -1, 0), seed=seed, segs=20, rings=16,
                            cut=cut, bumps=0.04, power=power)
    prof = geo.carrot_profile(L, R, rings=16, power=power)
    return obj, (lambda y: carrot_radius(prof, y - y_tip)), y_tip + L


def barbed_wire(name, radius_at, y0, y1, turns, mat, seed=0, barbs_per_turn=3):
    """Two twisted steel strands spiralling round a club, with four-point barbs."""
    rng = random.Random(seed)
    n = int(turns * 28)
    strands = [[], []]
    frames = []
    for k in range(n + 1):
        q = k / n
        y = y0 + (y1 - y0) * q
        a = turns * TAU * q
        rr = radius_at(y) + 0.0032
        p = Vector((rr * math.cos(a), y, rr * math.sin(a)))
        nrm = Vector((math.cos(a), 0, math.sin(a)))
        tan = Vector((-math.sin(a) * rr * turns * TAU, (y1 - y0), math.cos(a) * rr * turns * TAU)).normalized()
        b = tan.cross(nrm)
        frames.append((p, nrm, tan, b))
        twist = q * turns * 9 * TAU
        for s in range(2):
            ph = twist + s * math.pi
            strands[s].append(p + (nrm * math.cos(ph) + b * math.sin(ph)) * 0.0013)
    out = [geo.sweep(f"{name}_{s}", strands[s], 0.0011, segs=5, mat=mat) for s in range(2)]
    nb = int(turns * barbs_per_turn)
    for k in range(nb):
        p, nrm, tan, b = frames[int((k + 0.5) / nb * n)]
        out.append(parts.band(f"{name}_coil{k}", p, tan, 0.0024, 0.004, mat, segs=8))
        for j, d in enumerate((nrm * 0.75 + tan * 0.66, nrm * 0.75 - tan * 0.66, nrm * 0.7 + b * 0.7,
                               nrm * 0.7 - b * 0.7)):
            d = (d + Vector(tuple(rng.uniform(-0.15, 0.15) for _ in range(3)))).normalized()
            out.append(geo.sweep(f"{name}_barb{k}_{j}", [p, p + d * 0.006, p + d * 0.012],
                                 [0.0011, 0.0009, 0.00025], segs=5, mat=mat, caps=True))
    return out


def build_melee_barbed_carrot():
    m = M()
    objs = []
    carrot, rad, crown = _carrot_club("carrot", 0.42, 0.05, -0.125, 0.13, seed=11)
    objs.append(carrot)
    # leather grip over the tapering tip, a twine knot at each end, a brass pommel cap
    objs.append(wrap("grip", rad, -0.066, 0.06, m["leather"], extra=0.0026))
    objs += parts.knot("grip_knot", (0, 0.062, rad(0.062) + 0.002), 0.006, seed=3, tail_dir=(0.2, 0.1, -1))
    objs.append(parts.band("pommel", (0, -0.069, 0), (0, 1, 0), rad(-0.069) + 0.0012, 0.006, m["brass"], segs=14))
    # barbed wire round the fat end, bloodied where it bites
    objs += barbed_wire("wire", rad, 0.135, 0.275, 3.2, m["steel"], seed=5)
    objs += splatter("blood", (0, 0.215, 0), (0, 1, 0), rad(0.215) + 0.002, 9, m["blood"], seed=7, size=0.007,
                     drips=3, drip_len=0.022)
    objs += splatter("blood_old", (0, 0.17, 0), (0, 1, 0), rad(0.17) + 0.0015, 5, m["blood_dry"], seed=21,
                     size=0.008)
    # cropped carrot greens out of the crown
    objs.append(parts.greens("greens", (0, crown + 0.004, 0), length=0.055, direction=(0, 1, 0.35), stems=4,
                             seed=4, pairs=2, lobes=2, spread=35.0))
    return {"objects": objs, "markers": {"Tip": (0, crown, 0)},
            "report": report("Carrot club held by its tapering tip; barbed wire round the fat crown end.")}


# --------------------------------------------------------------------------- Bandit Bunny: shadow carrot

def _shadow_skin(nb):
    vec = nb.coords("Object", 1.0)
    nz = nb.noise(vec, scale=22.0, detail=6.0, rough=0.6)
    # thin wandering veins where the noise crosses its mid value
    vein = nb.math("SUBTRACT", 1.0, nb.math("MULTIPLY", nb.math("ABSOLUTE", nb.math("SUBTRACT", nz.outputs["Fac"], 0.5)),
                                             26.0), clamp=True)
    base = nb.mix(0.35, mats.srgb("#1a1224"), nb.noise(vec, scale=110.0).outputs["Color"], blend="OVERLAY")
    nb.set("Base Color", nb.mix(vein, base, mats.srgb("#b884ff")))
    nb.set("Roughness", nb.mix(vein, 0.32, 0.12, data="FLOAT"))
    nb.set("Coat Weight", 0.4)
    nb.set("Normal", nb.bump(nb.math("SUBTRACT", 1.0, vein), 0.45, 0.0012))


def build_melee_shadow_carrot():
    m = M()
    objs = []
    carrot, rad, crown = _carrot_club("carrot", 0.42, 0.048, -0.125, 0.13, seed=29, power=1.3)
    carrot.data.materials[0] = custom("shadow_skin", _shadow_skin)
    objs.append(carrot)
    objs.append(wrap("grip", rad, -0.066, 0.06, mats.leather("leather_black", tint="#2a2230"), extra=0.0026))
    objs += parts.knot("grip_knot", (0, 0.062, rad(0.062) + 0.002), 0.006, seed=8, tail_dir=(-0.2, 0.1, -1))
    objs.append(parts.band("pommel", (0, -0.069, 0), (0, 1, 0), rad(-0.069) + 0.0012, 0.006,
                           mats.metal("black_iron", "iron", tint="#2c2833"), segs=14))
    # black thorns growing out of the striking end
    thorn = mats.plain("thorn", "#120c18", rough=0.2, coat=0.6, noise_amt=0.1)
    rng = random.Random(13)
    for k in range(11):
        y = rng.uniform(0.12, 0.27)
        a = rng.uniform(0, TAU)
        nrm = Vector((math.cos(a), 0, math.sin(a)))
        base = Vector((0, y, 0)) + nrm * (rad(y) - 0.002)
        d = (nrm + Vector((0, rng.uniform(0.1, 0.5), 0))).normalized()
        L = rng.uniform(0.014, 0.022)
        objs.append(geo.sweep(f"thorn{k}", [base, base + d * L * 0.5, base + d * L],
                              [0.0042, 0.0022, 0.0002], segs=6, mat=thorn, caps=True))
    objs += splatter("blood", (0, 0.2, 0), (0, 1, 0), rad(0.2) + 0.002, 6, m["blood"], seed=17, size=0.006,
                     drips=2)
    leaf = mats.leaf("shadow_leaf", color="#2b1a3c", vein="#8d5ad6")
    objs.append(geo.carrot_greens("greens", length=0.06, stems=4, pairs=2, lobes=2, seed=9, mat=leaf,
                                  stem_mat=mats.leaf("shadow_stem", color="#22162e", vein="#5d3a8c"),
                                  direction=(0, 1, 0.3), spread=40.0, stem_r=0.0018))
    objs[-1].location = (0, crown + 0.004, 0)
    return {"objects": objs, "markers": {"Tip": (0, crown, 0)},
            "report": report("Near-black carrot with violet veins and black thorns.")}


# --------------------------------------------------------------------------- Frog: fly swatter

def _fly(name, centre, m):
    """A housefly squashed through the swatter mesh: body straddles the grid,
    wings splayed above, legs below, guts smeared round it."""
    c = Vector(centre)
    out = []
    black = mats.plain("fly_black", "#17181f", rough=0.3, coat=0.6, noise_amt=0.2, noise_scale=300.0)
    eye = mats.plain("fly_eye", "#8e1410", rough=0.15, coat=0.8, noise_amt=0.4, noise_scale=900.0, bump=0.4)
    wing = mats.plain("fly_wing", "#c9ccd2", rough=0.15, coat=0.3, noise_amt=0.1)
    guts = mats.plain("fly_guts", "#a8b34a", rough=0.15, coat=0.6, noise_amt=0.3)
    for part, (dy, r, sq) in {"abdomen": (-0.009, 0.0062, 0.62), "thorax": (0.002, 0.0055, 0.8)}.items():
        o = geo.lathe(f"{name}_{part}", [(-r * 1.2, 0.0), (-r * 0.6, r * 0.85), (0.0, r), (r * 0.6, r * 0.85),
                                          (r * 1.2, 0.0)], segs=12, mat=black, sharp_angle=None)
        o.scale = (1.0, 1.0, sq)
        o.location = c + Vector((0, dy, 0))
        out.append(o)
    head = c + Vector((0, 0.0105, 0.001))
    out.append(blob(f"{name}_head", head, 0.0038, black, (0, 0, 1), 0.8, 3, 0.05))
    for sx in (1, -1):
        out.append(blob(f"{name}_eye{sx}", head + Vector((sx * 0.0035, 0.0018, 0.0012)), 0.0031, eye, (sx, 0.3, 0.4),
                        0.85, 5, 0.03))
        wl = geo.lathe(f"{name}_wing{sx}", [(0.0, 0.0), (0.004, 0.0034), (0.011, 0.0042), (0.017, 0.0026),
                                            (0.02, 0.0)], segs=10, mat=wing, sharp_angle=None)
        wl.scale = (1.0, 1.0, 0.12)
        parts.orient(wl, (sx * 0.85, -0.5, 0.15), c + Vector((sx * 0.002, 0.0, 0.0035)))
        out.append(wl)
        for j, a in enumerate((-0.6, 0.0, 0.6)):
            d = Vector((sx * math.cos(a), math.sin(a) * 0.9, 0)).normalized()
            p0 = c + Vector((sx * 0.003, 0.0 + a * 0.004, -0.002))
            out.append(geo.sweep(f"{name}_leg{sx}{j}", [p0, p0 + d * 0.006 + Vector((0, 0, -0.003)),
                                                        p0 + d * 0.012 + Vector((0, 0, -0.0045))],
                                 [0.0007, 0.0006, 0.0004], segs=4, mat=black))
    out.append(blob(f"{name}_guts", c + Vector((0.002, -0.004, 0.0005)), 0.009, guts, (0, 0, 1), 0.18, 9, 0.5))
    out.append(blob(f"{name}_guts_b", c + Vector((-0.004, -0.003, -0.0016)), 0.007, guts, (0, 0, -1), 0.18, 12, 0.5))
    out.append(blob(f"{name}_red", c + Vector((-0.003, 0.007, 0.0007)), 0.004, m["blood"], (0, 0, 1), 0.2, 15, 0.5))
    return out


def build_melee_fly_swatter():
    m = M()
    objs = []
    plastic = mats.plain("swatter_red", "#d42b22", rough=0.35, coat=0.3, noise_amt=0.06, noise_scale=200.0)
    grip_green = mats.plain("grip_green", "#6fb43f", rough=0.5, noise_amt=0.1, noise_scale=300.0, bump=0.2)
    # ribbed grip + thin shaft
    rib = lambda i, j, a, t, r: r * (1.0 + 0.06 * max(0.0, math.sin(t * 420.0))) if 1 < i < 13 else r
    objs.append(geo.lathe("grip", [(-0.075, 0.0), (-0.074, 0.008), (-0.07, 0.0105)] +
                          [(-0.07 + 0.012 * k, 0.0105 + 0.0012 * math.sin(k * 0.6)) for k in range(1, 11)] +
                          [(0.058, 0.0085), (0.064, 0.0062)], segs=16, mat=grip_green, radius_fn=rib,
                          sharp_angle=None))
    objs.append(geo.cylinder("hang_hole_ring", 0.0045, 0.004, 12, grip_green, axis="X"))
    objs[-1].location = (0, -0.066, 0)
    objs.append(geo.cylinder("shaft", 0.0052, 0.17, 10, plastic, center=False))
    objs[-1].location = (0, 0.06, 0)
    # paddle: rounded-rectangle rim + a grid of bars, lying flat (faces +-Z)
    y0, y1, hw, cr = 0.226, 0.356, 0.056, 0.016
    rim = []
    for cx, cy, a0 in ((hw - cr, y1 - cr, 0), (-hw + cr, y1 - cr, 90), (-hw + cr, y0 + cr, 180), (hw - cr, y0 + cr, 270)):
        for k in range(5):
            a = math.radians(a0 + 90 * k / 4)
            rim.append((cx + cr * math.cos(a), cy + cr * math.sin(a), 0.0))
    objs.append(geo.sweep("rim", rim, 0.0032, segs=6, mat=plastic, closed=True, flatten=0.6, up=(0, 0, 1)))
    objs.append(geo.box("neck", (0.014, 0.03, 0.0048), (0, 0.214, 0), plastic, bevel=0.0015))
    pitch, bar = 0.0105, 0.0019
    xs = [-hw + 0.004 + pitch * k for k in range(int((2 * hw - 0.008) / pitch) + 1)]
    ys = [y0 + 0.004 + pitch * k for k in range(int((y1 - y0 - 0.008) / pitch) + 1)]
    for k, x in enumerate(xs):
        objs.append(geo.box(f"bar_y{k}", (bar, y1 - y0 - 0.004, 0.0024), (x, (y0 + y1) / 2, 0), plastic))
    for k, y in enumerate(ys):
        objs.append(geo.box(f"bar_x{k}", (2 * hw - 0.004, bar, 0.0024), (0, y, 0), plastic))
    objs += _fly("fly", (0.012, 0.29, 0.0), m)
    objs += [blob(f"smear{k}", (x, y, -0.0016), r, m["blood_dry"], (0, 0, -1), 0.15, 30 + k, 0.5)
             for k, (x, y, r) in enumerate(((-0.02, 0.25, 0.008), (0.03, 0.33, 0.006), (-0.035, 0.32, 0.005)))]
    return {"objects": objs, "markers": {"Tip": (0, y1, 0)},
            "report": report("Plastic swatter; the paddle lies flat (faces +-Y in Godot). Fly stuck through the mesh.")}


# --------------------------------------------------------------------------- Fox: bunny spine

def _vertebra(name, pos, r, mat, gristle, up_len, side_len, seed):
    out = []
    body = geo.lathe(f"{name}_body", [(-0.010 * r / 0.012, r * 0.82), (-0.008 * r / 0.012, r), (0.008 * r / 0.012, r),
                                      (0.010 * r / 0.012, r * 0.82)], segs=12, mat=mat, sharp_angle=None)
    geo.displace_noise(body, r * 0.06, 1.0 / r, seed)
    body.location = pos
    out.append(body)
    out.append(geo.sweep(f"{name}_spine", [pos + Vector((0, -0.002, r * 0.8)), pos + Vector((0, -0.004, r + up_len * 0.6)),
                                           pos + Vector((0, -0.007, r + up_len))],
                         [r * 0.42, r * 0.3, r * 0.14], segs=6, mat=mat, flatten=0.45, up=(0, 1, 0)))
    for sx in (1, -1):
        out.append(geo.sweep(f"{name}_side{sx}", [pos + Vector((sx * r * 0.7, 0, r * 0.2)),
                                                  pos + Vector((sx * (r + side_len), -0.002, r * 0.35))],
                             [r * 0.3, r * 0.14], segs=5, mat=mat, caps=True))
    return out


def _bunny_head(c, m):
    """A cartoon bunny's head (X-eyes, tongue out, ears flopped) on the end of
    its own spine, facing forward (+Y); `c` is the middle of the skull."""
    fur = mats.plain("bunny_fur", "#d9c4a4", rough=0.9, noise_amt=0.35, noise_scale=500.0, bump=0.5, sheen=0.6)
    pink = mats.plain("bunny_pink", "#e79aa2", rough=0.35, coat=0.3, noise_amt=0.15)
    ink = mats.plain("ink", "#191414", rough=0.4, noise_amt=0.05)
    tooth = mats.plain("tooth", "#f4efe2", rough=0.25, coat=0.4, noise_amt=0.05)
    out = []
    skull = geo.lathe("head", [(-0.034, 0.0), (-0.03, 0.019), (-0.018, 0.033), (0.0, 0.037), (0.016, 0.033),
                               (0.028, 0.022), (0.035, 0.0)], segs=20, mat=fur, sharp_angle=None)
    skull.scale = (0.95, 1.0, 0.92)
    skull.location = c
    out.append(skull)
    snout = c + Vector((0, 0.03, -0.01))
    for sx in (1, -1):
        cheek = geo.lathe(f"cheek{sx}", [(-0.012, 0.0), (-0.006, 0.011), (0.006, 0.011), (0.012, 0.0)], segs=12,
                          mat=fur, sharp_angle=None)
        cheek.location = snout + Vector((sx * 0.009, -0.002, 0))
        out.append(cheek)
        # X eyes
        e = c + Vector((sx * 0.026, 0.021, 0.01))
        n = Vector((sx * 0.75, 0.6, 0.25)).normalized()
        t1 = n.cross(Vector((0, 0, 1))).normalized()
        t2 = n.cross(t1).normalized()
        for d in (t1 + t2, t1 - t2):
            d = d.normalized() * 0.0065
            out.append(geo.sweep(f"x{sx}{d.x:.3f}", [e - d + n * 0.002, e + n * 0.0035, e + d + n * 0.002], 0.0013,
                                 segs=5, mat=ink, caps=True))
        # ears: long flat sweeps, one flopped down, one bent back
        root = c + Vector((sx * 0.013, -0.012, 0.03))
        if sx > 0:
            ear = [root, root + Vector((0.008, -0.01, 0.03)), root + Vector((0.02, -0.03, 0.045)),
                   root + Vector((0.034, -0.05, 0.035)), root + Vector((0.042, -0.06, 0.016))]
        else:
            ear = [root, root + Vector((-0.004, -0.018, 0.026)), root + Vector((-0.01, -0.045, 0.034)),
                   root + Vector((-0.014, -0.072, 0.026)), root + Vector((-0.016, -0.09, 0.012))]
        out.append(geo.sweep(f"ear{sx}", ear, [0.0075, 0.0105, 0.0115, 0.009, 0.004], segs=8, mat=fur,
                             flatten=0.3, up=(sx, 0, 0.3), caps=True))
        inner = [p + Vector((sx * 0.0008, 0.0, 0.0)) for p in ear[1:-1]]
        out.append(geo.sweep(f"ear_in{sx}", inner, [0.006, 0.0068, 0.0052], segs=8, mat=pink, flatten=0.2,
                             up=(sx, 0, 0.3), caps=True))
    out.append(blob("nose", snout + Vector((0, 0.012, 0.007)), 0.0055, pink, (0, 1, 0.3), 0.7, 2, 0.05))
    for sx in (1, -1):
        out.append(geo.box(f"tooth{sx}", (0.0055, 0.003, 0.0085), snout + Vector((sx * 0.003, 0.009, -0.011)), tooth,
                           bevel=0.0008))
    out.append(geo.sweep("tongue", [snout + Vector((0.004, 0.006, -0.012)), snout + Vector((0.009, 0.012, -0.02)),
                                    snout + Vector((0.012, 0.014, -0.03))],
                         [0.0045, 0.005, 0.0038], segs=8, mat=pink, flatten=0.35, up=(0, 1, 0), caps=True))
    return out


def build_melee_bunny_spine():
    m = M()
    objs = []
    # tail (grip) to neck: 12 vertebrae on a gentle S-curve, growing toward the neck
    n = 12
    pts = []
    for k in range(n):
        q = k / (n - 1)
        pts.append(Vector((0.0, -0.075 + q * 0.31, 0.007 * math.sin(q * math.pi * 1.6))))
    for k, p in enumerate(pts):
        q = k / (n - 1)
        r = 0.0085 + 0.0045 * q
        objs += _vertebra(f"v{k}", p, r, m["bone"], m["gristle"], 0.006 + 0.01 * q, 0.004 + 0.007 * q, seed=k)
        if k < n - 1:
            mid = (p + pts[k + 1]) / 2
            disc = geo.cylinder(f"disc{k}", r * 0.86, 0.006, 12, m["gristle"])
            disc.location = mid
            objs.append(disc)
    # three pairs of broken ribs near the neck
    for k, idx in enumerate((n - 4, n - 3, n - 2)):
        p = pts[idx]
        for sx in (1, -1):
            rib = [p + Vector((sx * 0.01, 0, 0.004)), p + Vector((sx * 0.028, -0.004, -0.008)),
                   p + Vector((sx * 0.036, -0.008, -0.028 + k * 0.006))]
            objs.append(geo.sweep(f"rib{k}{sx}", rib, [0.0034, 0.003, 0.0026], segs=6, mat=m["bone"], caps=True))
    # the head, with a ragged bloody neck
    neck = pts[-1] + Vector((0, 0.012, 0.004))
    head_c = neck + Vector((0, 0.03, 0.012))
    objs += scale_about(_bunny_head(head_c, m), neck, 1.25)
    head_c = neck + (head_c - neck) * 1.25
    objs.append(geo.lathe("neck_stump", [(-0.008, 0.012), (-0.002, 0.019), (0.006, 0.02), (0.012, 0.0)], segs=14,
                          mat=m["blood"], sharp_angle=None))
    objs[-1].location = neck + Vector((0, 0.002, 0.002))
    geo.displace_noise(objs[-1], 0.003, 160.0, 4)
    objs += splatter("blood", neck, (0, 1, 0), 0.016, 6, m["blood"], seed=33, size=0.006, drips=3, drip_len=0.03)
    objs += splatter("gore", pts[n // 2], (0, 1, 0), 0.012, 4, m["blood_dry"], seed=41, size=0.006)
    return {"objects": objs, "markers": {"Tip": tuple(head_c + Vector((0, 0.04, 0)))},
            "report": report("Bunny spine (12 vertebrae, discs, broken ribs) with the head still attached.")}


# --------------------------------------------------------------------------- Squirrel: acorn knocker

def build_melee_acorn_knocker():
    m = M()
    objs = []
    stick, spts, sr = wobbly_stick("stick", -0.08, 0.305, 0.0125, 0.0175, m["bark"], seed=6)
    objs.append(stick)
    objs.append(twig("twig_a", spts[4] + Vector((0.009, 0, 0.004)), (1, 0.6, 0.5), 0.03, 0.004, m["bark"], 2))
    objs.append(twig("twig_b", spts[6] + Vector((-0.012, 0, 0)), (-1, 0.8, -0.3), 0.022, 0.0035, m["bark"], 3))
    objs.append(wrap("grip", lambda y: 0.0125 + 0.0005 * (y + 0.08) / 0.385 * 10, -0.07, 0.05, m["twine_wrap"],
                     extra=0.0028))
    # the cord: tied round the end, hanging down off the striking (-Z) side
    end = spts[-1]
    tie_y = end.y - 0.014
    objs.append(parts.band("tie", (end.x, tie_y, end.z), (0, 1, 0), 0.0182, 0.006, m["twine"], segs=14))
    top = Vector((end.x, tie_y, end.z - 0.018))
    cord = [top, top + Vector((0.002, 0.012, -0.02)), top + Vector((0.004, 0.022, -0.042)),
            top + Vector((0.004, 0.026, -0.058))]
    objs.append(geo.sweep("cord", cord, 0.0016, segs=6, mat=m["twine"]))
    objs += parts.knot("tie_knot", top + Vector((0, 0, 0.002)), 0.0055, seed=12, tail_dir=(0.3, -0.4, -0.6))
    # the acorn, hanging cap-up from the cord
    hang = cord[-1]
    shell = geo.lathe("acorn_shell", [(0.0, 0.0145), (0.008, 0.0165), (0.02, 0.0152), (0.032, 0.011), (0.041, 0.0045),
                                      (0.045, 0.0)], segs=18, mat=mats.acorn("acorn_shell", "shell", tint="#d08a55",
                                                                             rough=0.24),
                      axis="-Z", sharp_angle=None, v_norm=True)
    shell["bbd_uv"] = "src"
    shell.location = hang + Vector((0, 0, -0.012))
    objs.append(shell)
    cap = geo.lathe("acorn_cap", [(-0.003, 0.0), (0.0, 0.012), (0.004, 0.0172), (0.011, 0.0178), (0.016, 0.0148),
                                  (0.0185, 0.0)], segs=18, mat=mats.acorn("acorn_cap", "cap", tint="#7f6a52", rough=0.8),
                    axis="Z", sharp_angle=None, v_norm=True)
    cap["bbd_uv"] = "src"
    cap.location = hang + Vector((0, 0, -0.0125))
    objs.append(cap)
    objs.append(geo.cylinder("acorn_stem", 0.0022, 0.008, 6, mats.acorn("acorn_stem", "cap", tint="#a08868"),
                             axis="Z"))
    objs[-1].location = hang + Vector((0, 0, 0.004))
    bottom = hang + Vector((0, 0, -0.057))
    objs += splatter("blood", hang + Vector((0, 0, -0.035)), (0, 0, 1), 0.0158, 8, m["blood"], seed=19,
                     size=0.0065)
    objs.append(drip("acorn_drip", bottom + Vector((0, 0, 0.004)), 0.016, 0.0024, m["blood"], seed=2))
    objs += splatter("stick_blood", (0, end.y - 0.04, end.z), (0, 1, 0), 0.0175, 5, m["blood_dry"], seed=23,
                     size=0.006, drips=1)
    return {"objects": objs, "markers": {"Tip": tuple(end)},
            "report": report("Bark stick; a bloody acorn hangs on a twine cord off the striking end.")}


# --------------------------------------------------------------------------- Hamster: mousetrap mallet

def build_melee_mousetrap_mallet():
    m = M()
    objs = []
    paint = mats.plain("pencil_yellow", "#f0bb22", rough=0.35, coat=0.4, noise_amt=0.05)
    eraser = mats.plain("eraser", "#e98a9a", rough=0.8, noise_amt=0.15, noise_scale=300.0, bump=0.2)
    trap_wood = mats.wood("trap_wood", "coated_pine", coords="box", tint="#f0d3a8", rough=0.6)
    cheese = mats.plain("cheese", "#f3c43d", rough=0.45, noise_amt=0.15, noise_scale=120.0, bump=0.2)
    tail_pink = mats.plain("tail_pink", "#e3a1a4", rough=0.45, noise_amt=0.2, noise_scale=400.0, bump=0.3)
    # hexagonal pencil, ferrule + eraser at the butt
    objs.append(geo.lathe("pencil", [(-0.078, 0.0108), (0.214, 0.0108)], segs=6, mat=paint, sharp_angle=20,
                          phase=math.pi / 6))
    objs.append(parts.band("ferrule", (0, -0.084, 0), (0, 1, 0), 0.0112, 0.014, m["brass"], segs=16))
    objs.append(geo.cylinder("eraser", 0.0104, 0.016, 16, eraser, bevel=0.003))
    objs[-1].location = (0, -0.098, 0)
    # the trap: a board lying flat on the end of the pencil (its bottom leads the swing),
    # modelled at real-trap proportions and then grown to read at arm's length
    handle = len(objs)
    by0, by1, bw, bt = 0.2, 0.33, 0.026, 0.009
    objs.append(geo.box("board", (bw * 2, by1 - by0, bt), (0, (by0 + by1) / 2, 0.0), trap_wood, bevel=0.0012))
    top = bt / 2
    # spring coils either side, the U-shaped kill bar snapped shut across the board
    sy = 0.262
    for sx in (1, -1):
        coil = geo.helix((sx * 0.012, sy, top + 0.006), (sx, 0, 0), 0.0055, 0.0019, 4.5, pts_per_turn=12)
        objs.append(geo.sweep(f"spring{sx}", coil, 0.0011, segs=5, mat=m["steel"]))
    bar = [Vector((0.021, sy, top + 0.006)), Vector((0.021, sy + 0.03, top + 0.0022)), Vector((0.021, by1 - 0.012,
                                                                                               top + 0.0018)),
           Vector((-0.021, by1 - 0.012, top + 0.0018)), Vector((-0.021, sy + 0.03, top + 0.0022)),
           Vector((-0.021, sy, top + 0.006))]
    objs.append(geo.sweep("kill_bar", smooth3(bar), 0.0013, segs=6, mat=m["steel"]))
    objs.append(geo.sweep("arm", [Vector((0, sy - 0.004, top + 0.0024)), Vector((0, 0.215, top + 0.0018))], 0.0009,
                          segs=5, mat=m["steel"]))
    objs.append(geo.box("pedal", (0.016, 0.022, 0.0015), (0, 0.236, top + 0.0008), m["steel"], bevel=0.0004))
    for k, (x, y) in enumerate(((0.019, 0.206), (-0.019, 0.206), (0.019, by1 - 0.006), (-0.019, by1 - 0.006))):
        objs.append(parts.rivet(f"staple{k}", (x, y, top), (0, 0, 1), 0.0018, m["steel"], segs=6))
    # a cheese wedge on the pedal
    wedge = [(0.0, 0.0), (0.024, 0.0), (0.0, 0.016)]
    objs.append(geo.extrude_outline("cheese", wedge, 0.016, cheese, plane="YZ", bevel=0.001))
    objs[-1].location = (0, 0.226, top + 0.0016)
    for k, (x, y, r) in enumerate(((0.0081, 0.231, 0.0028), (-0.0081, 0.236, 0.0022), (0.0081, 0.24, 0.0018))):
        objs.append(blob(f"cheese_hole{k}", (x, y, top + 0.006), r, mats.plain("cheese_dark", "#c4901f", rough=0.5),
                         (1 if x > 0 else -1, 0, 0), 0.25, k, 0.05))
    # whoever got caught: a pink tail pinned under the bar, curling off the side
    pin = Vector((0.004, by1 - 0.012, top + 0.003))
    tail = [pin + Vector((-0.006, 0.002, 0)), pin, pin + Vector((0.02, 0.004, 0.004)), pin + Vector((0.036, -0.006, 0.01)),
            pin + Vector((0.042, -0.022, 0.016)), pin + Vector((0.036, -0.034, 0.024)), pin + Vector((0.026, -0.032, 0.03))]
    objs.append(geo.sweep("tail", tail, [0.0032, 0.003, 0.0026, 0.0021, 0.0016, 0.0011, 0.0006], segs=8,
                          mat=tail_pink, caps=True))
    objs += [blob(f"tail_blood{k}", pin + off, r, m["blood"], (0, 0, 1), 0.3, 40 + k)
             for k, (off, r) in enumerate(((Vector((-0.004, 0.0, 0.0)), 0.0055), (Vector((-0.012, -0.004, -0.001)),
                                                                                  0.0045)))]
    # the business side (bottom) is splattered
    objs += [blob(f"under{k}", (x, y, -bt / 2 - 0.0006), r, m["blood" if k % 2 else "blood_dry"], (0, 0, -1), 0.2,
                  50 + k) for k, (x, y, r) in enumerate(((0.008, 0.25, 0.01), (-0.014, 0.3, 0.008),
                                                         (0.016, 0.31, 0.006), (-0.006, 0.22, 0.005)))]
    objs.append(drip("under_drip", (0.016, 0.31, -bt / 2 - 0.001), 0.014, 0.0022, m["blood"], seed=6))
    TRAP = 1.45
    scale_about(objs[handle:], (0, by0, 0), TRAP)
    return {"objects": objs, "markers": {"Tip": (0, by0 + (by1 - by0) * TRAP, 0)},
            "report": report("Pencil handle; a sprung mousetrap board on the end, flat side down.")}


# --------------------------------------------------------------------------- Raccoon: rusty-nail corncob

def _corn(nb):
    vec = nb.coords("Object", 1.0)
    nz = nb.noise(vec, scale=55.0, detail=3.0)
    gnaw = nb.math("GREATER_THAN", nb.noise(nb.coords("Object", 1.0, loc=(3.1, 0.7, 1.9)), scale=34.0,
                                            detail=2.0).outputs["Fac"], 0.6)
    kernel = nb.mix(0.25, mats.srgb("#f1c33f"), nz.outputs["Color"], blend="OVERLAY")
    cob = nb.mix(0.3, mats.srgb("#c49a6c"), nz.outputs["Color"], blend="OVERLAY")
    nb.set("Base Color", nb.mix(gnaw, kernel, cob))
    nb.set("Roughness", nb.mix(gnaw, 0.3, 0.75, data="FLOAT"))
    nb.set("Coat Weight", 0.3)


def build_melee_nail_corncob():
    m = M()
    objs = []
    objs.append(geo.cylinder("dowel", 0.0115, 0.2, 14, m["pine"], center=False, bevel=0.002))
    objs[-1].location = (0, -0.08, 0)
    objs.append(wrap("grip", lambda y: 0.0115, -0.068, 0.045, m["twine_wrap"], extra=0.0028))
    # the cob: kernels in rows, some gnawed off down to the core
    y0, L, R, rows = 0.105, 0.24, 0.028, 14
    gnaw_rng = random.Random(4)
    gnawed = {(gnaw_rng.randrange(rows), gnaw_rng.randrange(24)) for _ in range(30)}

    def kernels(i, j, a, t, r):
        if r < R * 0.5:
            return r
        col = int((a % TAU) / TAU * rows) % rows
        rowk = int((t - y0) / L * 24)
        bump = max(0.0, math.sin((a % TAU) / TAU * rows * math.pi)) ** 0.5 * max(0.0, math.sin((t - y0) / L * 24 * math.pi)) ** 0.5
        if (col, rowk) in gnawed or (col + 1, rowk) in gnawed:
            return r * 0.78
        return r * (0.9 + 0.14 * bump)

    prof = [(y0 - 0.004, 0.0), (y0, R * 0.7), (y0 + 0.012, R * 0.95)] + \
           [(y0 + L * q, R * (1.0 - 0.25 * q * q)) for q in (0.1, 0.25, 0.4, 0.55, 0.7, 0.82, 0.92)] + \
           [(y0 + L * 0.98, R * 0.55), (y0 + L, 0.0)]
    dense = []
    for (t0, r0), (t1, r1) in zip(prof, prof[1:]):
        for k in range(4):
            q = k / 4
            dense.append((t0 + (t1 - t0) * q, r0 + (r1 - r0) * q))
    dense.append(prof[-1])
    cob = geo.lathe("cob", dense, segs=56, mat=custom("corn", _corn), radius_fn=kernels, sharp_angle=None)
    objs.append(cob)
    # husk leaves peeled back over the dowel
    husk = mats.leaf("husk", color="#c8c48a", vein="#e7e0b4", rough=0.6)
    for k in range(4):
        a = k / 4 * TAU + 0.4
        nrm = Vector((math.cos(a), 0, math.sin(a)))
        base = Vector((0, y0 + 0.01, 0)) + nrm * R * 0.8
        pts = [base, base + nrm * 0.008 + Vector((0, -0.02, 0)), base + nrm * 0.016 + Vector((0, -0.05, 0)),
               base + nrm * 0.018 + Vector((0, -0.075, 0))]
        objs.append(geo.sweep(f"husk{k}", pts, [0.012, 0.014, 0.011, 0.002], segs=8, mat=husk, flatten=0.15,
                              up=tuple(nrm), caps=True))
    # rusty nails hammered through from the inside, points out
    rng = random.Random(9)
    for k in range(10):
        a = rng.uniform(0, TAU) if k > 2 else -math.pi / 2 + rng.uniform(-0.6, 0.6)
        t = y0 + L * rng.uniform(0.2, 0.85)
        nrm = Vector((math.cos(a), rng.uniform(-0.15, 0.25), math.sin(a))).normalized()
        base = Vector((0, t, 0)) + nrm * R * 0.5
        shank = [base, base + nrm * 0.036, base + nrm * 0.046]
        objs.append(geo.sweep(f"nail{k}", shank, [0.0023, 0.0023, 0.0002], segs=6, mat=m["rust"], caps=True))
        if k < 4:
            objs.append(blob(f"nail_blood{k}", base + nrm * 0.04, 0.0038, m["blood"], nrm, 0.6, 60 + k))
    objs += splatter("blood", (0, y0 + L * 0.55, 0), (0, 1, 0), R * 0.98, 7, m["blood"], seed=71, size=0.0075,
                     drips=2)
    return {"objects": objs, "markers": {"Tip": (0, y0 + L, 0)},
            "report": report("Corncob on a pine dowel, gnawed patches, rusty nails through it.")}


# --------------------------------------------------------------------------- Beaver: trout on a stick

def _trout(nb):
    pos = nb.add("ShaderNodeTexCoord").outputs["Object"]
    sep = nb.add("ShaderNodeSeparateXYZ")
    nb.link(pos, sep.inputs[0])
    z = nb.math("MULTIPLY", nb.math("ADD", sep.outputs["Z"], 0.024), 21.0)      # 0 belly .. 1 back
    col = nb.ramp(z, [(0.0, mats.srgb("#f2ece0")), (0.38, mats.srgb("#e8d8c4")), (0.5, mats.srgb("#d98a86")),
                      (0.62, mats.srgb("#9a9a62")), (1.0, mats.srgb("#4f5a34"))])
    vor = nb.add("ShaderNodeTexVoronoi")
    vor.inputs["Scale"].default_value = 260.0
    nb.link(nb.coords("Object", 1.0), vor.inputs["Vector"])
    spots = nb.math("MULTIPLY", nb.math("LESS_THAN", vor.outputs["Distance"], 0.16), nb.math("GREATER_THAN", z, 0.48))
    col = nb.mix(spots, col, mats.srgb("#1e1a17"))
    nb.set("Base Color", col)
    nb.set("Roughness", 0.22)
    nb.set("Coat Weight", 0.8)
    nb.set("Normal", nb.bump(nb.noise(nb.coords("Object", 1.0), scale=900.0, detail=2.0).outputs["Fac"], 0.12, 0.0004))


def build_melee_trout_stick():
    m = M()
    objs = []
    stick, spts, sr = wobbly_stick("branch", -0.08, 0.29, 0.0125, 0.0115, m["bark"], seed=14, wiggle=0.004)
    objs.append(stick)
    objs.append(wrap("grip", lambda y: 0.0125, -0.07, 0.05, m["twine_wrap"], extra=0.0028))
    # beaver-gnawed point (pale wood, chisel facets)
    tip0 = spts[-1]
    point = geo.lathe("gnawed_point", [(0.0, 0.0115), (0.012, 0.0095), (0.026, 0.005), (0.04, 0.0)], segs=7,
                      mat=mats.wood("gnawed", "coated_pine", coords="box", tint="#f2dcb6", rough=0.7),
                      sharp_angle=20)
    geo.displace_noise(point, 0.0012, 180.0, 3)
    point.location = tip0
    objs.append(point)
    # the trout, skewered mouth to tail along the stick
    fy0, fy1 = 0.105, 0.265
    fl = fy1 - fy0
    body = geo.lathe("trout", [(fy0 + fl * q, 0.024 * r) for q, r in
                               ((0.0, 0.18), (0.04, 0.42), (0.14, 0.78), (0.32, 0.98), (0.5, 1.0), (0.68, 0.9),
                                (0.84, 0.66), (0.94, 0.42), (1.0, 0.0))],
                     segs=20, mat=custom("trout_skin", _trout), sharp_angle=None)
    body.scale = (0.5, 1.0, 1.0)
    objs.append(body)
    fin = mats.plain("trout_fin", "#9d8f6a", rough=0.35, coat=0.3, noise_amt=0.2)
    tail = [(0.0, 0.0), (-0.012, 0.016), (-0.028, 0.024), (-0.022, 0.0), (-0.028, -0.022), (-0.012, -0.014)]
    objs.append(geo.extrude_outline("tail_fin", geo.chaikin(tail, 1, sharp=(2, 4)), 0.002, fin, plane="YZ",
                                    bevel=0.0006))
    objs[-1].location = (0, fy0 + 0.004, 0)
    dorsal = [(0.0, 0.0), (0.014, 0.012), (0.03, 0.01), (0.034, 0.0)]
    objs.append(geo.extrude_outline("dorsal_fin", dorsal, 0.0016, fin, plane="YZ", bevel=0.0005))
    objs[-1].location = (0, fy0 + fl * 0.42, 0.0225)
    for sx in (1, -1):
        eye_c = Vector((sx * 0.0085, fy0 + fl * 0.86, 0.006))
        objs.append(blob(f"eye{sx}", eye_c, 0.0042, mats.plain("fish_eye", "#e9e2c8", rough=0.2, coat=0.6),
                         (sx, 0, 0), 0.7, sx + 3, 0.02))
        objs.append(blob(f"pupil{sx}", eye_c + Vector((sx * 0.0024, 0.0006, 0)), 0.0024,
                         mats.plain("fish_pupil", "#111111", rough=0.15, coat=0.8), (sx, 0, 0), 0.5, sx + 7, 0.02))
        pec = [(0.0, 0.0), (-0.012, -0.004), (-0.018, -0.012), (-0.006, -0.008)]
        objs.append(geo.extrude_outline(f"pec{sx}", pec, 0.0014, fin, plane="YZ", bevel=0.0004))
        objs[-1].location = (sx * 0.0115, fy0 + fl * 0.72, -0.008)
        objs.append(geo.sweep(f"gill{sx}", [Vector((sx * 0.0105, fy0 + fl * 0.76, 0.012)),
                                            Vector((sx * 0.0122, fy0 + fl * 0.74, 0.0)),
                                            Vector((sx * 0.0105, fy0 + fl * 0.76, -0.012))],
                              0.0009, segs=4, mat=mats.plain("gill", "#8c3a3a", rough=0.3)))
    # where the stick goes in and comes out
    objs.append(blob("mouth_blood", (0, fy1 - 0.002, 0), 0.0072, m["blood"], (0, 1, 0), 0.35, 81))
    objs.append(blob("vent_blood", (0, fy0 + 0.006, -0.003), 0.006, m["blood"], (0, -1, -0.4), 0.35, 82))
    objs.append(drip("fish_drip", (0, fy0 + fl * 0.5, -0.024), 0.02, 0.0024, m["blood"], seed=8))
    return {"objects": objs, "markers": {"Tip": tuple(tip0 + Vector((0, 0.04, 0)))},
            "report": report("Gnawed branch with a trout skewered mouth-to-tail near the point.")}


def _entry(build, use):
    return dict(build=build, out="weapons", tex=1024, kind="melee", target=0.42, use=use)


ASSETS = {
    "melee_barbed_carrot": _entry(build_melee_barbed_carrot, "Bun's club: a carrot wrapped in barbed wire"),
    "melee_shadow_carrot": _entry(build_melee_shadow_carrot, "Bandit Bunny's club: a shadow carrot with thorns"),
    "melee_fly_swatter": _entry(build_melee_fly_swatter, "Frog's club: a fly swatter with a dead fly stuck in it"),
    "melee_bunny_spine": _entry(build_melee_bunny_spine, "Fox's club: a bunny spine with the head still attached"),
    "melee_acorn_knocker": _entry(build_melee_acorn_knocker, "Squirrel's club: a stick with a bloody acorn dangling"),
    "melee_mousetrap_mallet": _entry(build_melee_mousetrap_mallet, "Hamster's club: a pencil with a sprung mousetrap"),
    "melee_nail_corncob": _entry(build_melee_nail_corncob, "Raccoon's club: a corncob with rusty nails"),
    "melee_trout_stick": _entry(build_melee_trout_stick, "Beaver's club: a gnawed branch with a skewered trout"),
}
