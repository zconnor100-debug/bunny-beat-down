"""Pickups, crates, supply drop and the dandelion glider.

Blender space: front faces -Y (glTF +Z), +Z up, metres. Pickups and crates have
their origin at the bottom centre (they rest on the ground; game code can bob
and spin them). The glider's origin is the hand grip.
"""
from __future__ import annotations

import math
import random

import bpy
from mathutils import Matrix, Vector

from bbd import geo, mats, parts, plants, textures
from bbd.util import place

from assets.projectiles import build_carrot_shell_pellet, carrot_rocket_parts


def M():
    return {
        "pine": mats.wood("pine", "coated_pine", coords="src", tint="#e8c9a0", rough=0.5),
        "pine_box": mats.wood("pine_box", "coated_pine", coords="box", tint="#d4bea0", rough=0.6),
        "crate": mats.wood("crate_wood", "rough_wood", coords="box", tint="#d8c3a2", rough=0.8, wear=0.25, dirt=0.6),
        "iron": mats.metal("iron", "iron", wear=0.4),
        "brass": mats.metal("brass", "brass", wear=0.6),
        "galv": mats.metal("galv", "galv", tint="#8d9192"),
        "leather": mats.leather("leather"),
        "burlap": mats.burlap("burlap"),
        "twine": mats.fibre("twine"),
        "orange": mats.paint("paint_orange", "#e2701c", under="iron", chip=0.7),
        "sage": mats.paint("paint_sage", "#5d7a46", under="galv", chip=0.65),
        "cork": mats.plain("cork", "#b8875a", rough=0.85, noise_amt=0.35, noise_scale=180.0, bump=0.4),
        "tea": mats.plain("tea_glass", "#c27310", rough=0.06, coat=1.0, noise_amt=0.05),
        "glass": mats.plain("glass_air", "#a9b9ad", rough=0.05, coat=1.0, noise_amt=0.03),
    }


def tag(objs, node):
    for o in objs:
        o["bbd_node"] = node
    return objs


# --------------------------------------------------------------------------- pickups

def build_pickup_health():
    """Corked flask of dandelion tea with a four-leaf clover tied to its neck."""
    m = M()
    objs = []
    # flask: round belly, tea up to ~65 %, air-glass above
    belly = [(0.0, 0.0), (0.003, 0.050), (0.012, 0.075), (0.035, 0.092), (0.070, 0.098), (0.105, 0.092),
             (0.135, 0.072), (0.155, 0.048), (0.170, 0.030), (0.185, 0.026), (0.232, 0.025), (0.238, 0.030),
             (0.244, 0.030), (0.248, 0.026)]
    flask = geo.lathe("flask", belly, segs=28, mat=m["tea"], cap1=False, axis="Z", sharp=(11, 12), sharp_angle=None)
    flask.data.materials.append(m["glass"])
    for p in flask.data.polygons:
        if p.center.z > 0.118:
            p.material_index = 1
    objs.append(flask)
    cork = geo.lathe("cork", [(0.226, 0.0), (0.226, 0.021), (0.250, 0.023), (0.268, 0.026), (0.270, 0.020),
                              (0.270, 0.0)], segs=16, mat=m["cork"], axis="Z", sharp_angle=40)
    objs.append(cork)
    objs.append(parts.twine_sleeve("neck_twine", (0, 0, 0.205), (0, 0, 1), 0.0262, 0.016, rings=2))
    objs += parts.knot("neck_knot", (0.0, -0.030, 0.205), 0.007, seed=3, tail_dir=(0.2, -0.4, -1.0))
    # the four-leaf clover hanging on the front + a dandelion flower tucked in the twine
    objs.append(plants.clover("clover", (0.010, -0.106, 0.118), 0.058, normal=(0.05, -1.0, 0.25),
                              up_hint=(0, 0, 1), stem_len=0.07, seed=2))
    stem = geo.sweep("clover_tie", [Vector((0.010, -0.100, 0.118)), Vector((0.006, -0.085, 0.150)),
                                    Vector((0.0, -0.040, 0.198))], 0.0018, segs=5, mat=m["twine"])
    stem["bbd_uv"] = "src"
    objs.append(stem)
    objs.append(plants.dandelion_flower("flower", (0.028, -0.026, 0.214), 0.022, normal=(0.6, -0.7, 0.4)))
    return {"objects": objs, "markers": {},
            "report": {"notes": "Origin at the bottom centre. Readable pair: amber tea flask + green clover."}}


def build_pickup_armor():
    """Bark breastplate: three shingled pine-bark lames wrapped round a torso, an
    acorn-shell boss, brass rivets and leather shoulder / side straps."""
    m = M()
    bark = mats.bark("bark", density=2.2)
    shell = mats.acorn("acorn_shell_boss", "shell", tint="#d08a55", rough=0.24)
    objs = []
    R0, H, TH = 0.175, 0.40, 0.016
    SPAN = math.radians(72)

    def radius(level, z):
        """Torso wrap radius: upper lames sit outside the lower ones; chest bulges."""
        return R0 + 0.011 * level + 0.012 * math.sin(math.pi * min(1.0, z / H))

    def surf(level, theta, z):
        r = radius(level, z)
        return Vector((r * math.sin(theta), -r * math.cos(theta), z))

    def plate(name, level, z0, z1, top_curve, bottom_curve, nx=14, ny=4):
        import bmesh
        bm = bmesh.new()
        uvl = bm.loops.layers.uv.new("src")
        grid = []
        for j in range(ny + 1):
            row = []
            for i in range(nx + 1):
                s_ = -1.0 + 2.0 * i / nx
                zb, zt = z0 + bottom_curve(s_), z1 + top_curve(s_)
                z = zb + (zt - zb) * j / ny
                row.append(bm.verts.new(surf(level, s_ * SPAN, z)))
            grid.append(row)
        for j in range(ny):
            for i in range(nx):
                f = bm.faces.new((grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]))
                for loop in f.loops:
                    loop[uvl].uv = (loop.vert.co.x, loop.vert.co.z)
        obj = geo.finish(bm, name, bark, sharp_angle=None)
        mod = obj.modifiers.new("solid", "SOLIDIFY")
        mod.thickness = TH
        mod.offset = -1.0          # grow inward, the outer face stays on surf()
        mod.use_even_offset = True
        geo.bevel_and_normals(obj, 0.004, 1, angle=40)
        return obj

    neck = lambda s_: -0.08 * max(0.0, 1.0 - (s_ / 0.42) ** 2)
    arm = lambda s_: -0.075 * max(0.0, (abs(s_) - 0.62) / 0.38) ** 1.4
    flat = lambda s_: 0.0
    objs.append(plate("lame_top", 2, 0.225, 0.40, lambda s_: neck(s_) + arm(s_), lambda s_: -0.012 * (1 - s_ * s_)))
    objs.append(plate("lame_mid", 1, 0.118, 0.248, flat, lambda s_: -0.010 * (1 - s_ * s_), ny=3))
    objs.append(plate("lame_low", 0, 0.0, 0.140, flat, lambda s_: 0.014 * s_ * s_, ny=3))
    # acorn-shell boss with a brass rim
    bz = 0.31
    bpos = surf(2, 0.0, bz)
    boss = geo.lathe("boss", [(0.0, 0.050), (0.010, 0.048), (0.022, 0.036), (0.030, 0.018), (0.033, 0.0)],
                     segs=24, mat=shell, cap0=True, axis="-Y", sharp_angle=None)
    boss.location = bpos + Vector((0, 0.002, 0))
    objs.append(boss)
    objs.append(parts.band("boss_rim", bpos + Vector((0, 0.001, 0)), (0, -1, 0), 0.050, 0.010, m["brass"], segs=24))
    # brass rivets along each lame's lower edge
    for level, z in ((2, 0.236), (1, 0.128), (0, 0.012)):
        for k in range(-3, 4):
            th = k / 3.0 * SPAN * 0.85
            p = surf(level, th, z + 0.012)
            n = Vector((math.sin(th), -math.cos(th), 0.0))
            objs.append(parts.rivet(f"rv{level}{k}", p, n, 0.0045, m["brass"], segs=6))
    # leather shoulder loops (up over an imaginary shoulder and back down inside the
    # plate) + short side straps ending in brass buckles
    for sx in (1, -1):
        th = sx * SPAN * 0.62
        p0 = surf(2, th, 0.335)
        inside = surf(2, th * 0.92, 0.30) + Vector((0, 0.035, 0))
        pts = [p0 + Vector((0, -0.002, 0)), p0 + Vector((0, 0.005, 0.045)), Vector((p0.x * 0.97, p0.y + 0.045, 0.415)),
               Vector((p0.x * 0.95, p0.y + 0.09, 0.39)), inside + Vector((0, 0.01, 0.03)), inside]
        objs.append(geo.sweep(f"shoulder{sx}", pts, 0.020, segs=8, mat=m["leather"], flatten=0.22, up=(0, 0, 1)))
        objs.append(parts.rivet(f"shoulder_rv{sx}", p0 + Vector((0, -0.004, 0.012)), (math.sin(th), -math.cos(th), 0),
                                0.006, m["brass"], segs=6))
        e = surf(1, sx * SPAN, 0.19)
        tang = Vector((math.cos(sx * SPAN) * sx, math.sin(sx * SPAN) * sx, 0.0)).normalized()
        side = [e, e + tang * 0.03 + Vector((0, 0, -0.004)), e + tang * 0.065 + Vector((0, 0, -0.012))]
        objs.append(geo.sweep(f"side_strap{sx}", side, 0.016, segs=8, mat=m["leather"], flatten=0.22, up=(0, 0, 1)))
        bk = e + tang * 0.045
        objs.append(geo.sweep(f"buckle{sx}", [bk + Vector((0, 0, 0.022)) - tang * 0.012, bk + Vector((0, 0, -0.022)) - tang * 0.012,
                                               bk + Vector((0, 0, -0.022)) + tang * 0.012, bk + Vector((0, 0, 0.022)) + tang * 0.012],
                              0.0028, segs=6, mat=m["brass"], closed=True))
    return {"objects": objs, "markers": {},
            "report": {"notes": "Origin at the bottom centre; the plate faces +Z (front)."}}


def baby_carrot(name, length=0.2, radius=0.016, pos=(0, 0, 0), axis=(1, 0, 0), seed=0, tops=True, segs=10):
    """A garden carrot with a stub of cut green stems at the crown."""
    obj = parts.carrot_part(name, length, radius, pos=pos, axis=axis, seed=seed, segs=segs, rings=7, power=1.4,
                            bumps=0.06)
    out = [obj]
    if tops:
        d = Vector(axis).normalized()
        crown = Vector(pos) - d * length
        rng = random.Random(seed)
        for k in range(3):
            a = 2 * math.pi * k / 3 + rng.random()
            perp = d.orthogonal().normalized()
            q = perp * math.cos(a) * 0.006 + d.cross(perp) * math.sin(a) * 0.006
            st = [crown + q, crown + q * 1.3 - d * 0.018, crown + q * 1.8 - d * 0.034]
            out.append(geo.sweep(f"{name}_top{k}", st, 0.0022, segs=5,
                                 mat=mats.leaf("carrot_stem", color="#6a9a3a", vein="#8fbf5a")))
    return out


def build_ammo_light():
    """Seven garden carrots tied in a bundle with a twine bow."""
    objs = []
    R, L = 0.0165, 0.21
    rng = random.Random(4)
    pos = [(0.0, 0.0)] + [(2.05 * R * math.cos(a), 2.05 * R * math.sin(a)) for a in
                          [math.pi / 6 + k * math.pi / 3 for k in range(6)]]
    for k, (py, pz) in enumerate(pos):
        shift = rng.uniform(-0.012, 0.012)
        objs += baby_carrot(f"c{k}", L, R, pos=(L / 2 + shift, py, pz + 0.05), axis=(1, 0, 0), seed=70 + k)
    objs.append(parts.twine_sleeve("tie", (-0.01, 0, 0.05), (1, 0, 0), 3.0 * R + 0.002, 0.018, rings=2))
    objs += parts.knot("bow", (-0.01, 0.0, 0.05 + 3.0 * R + 0.006), 0.008, seed=2, tail_dir=(0.3, -0.6, -0.8))
    for sx in (1, -1):  # bow loops
        loop = geo.sweep(f"bow_loop{sx}", geo.arc_points((-0.01 + sx * 0.014, 0.0, 0.05 + 3.0 * R + 0.012), 0.012,
                                                         0, 330, 12, "XZ"), 0.0018, segs=5, mat=mats.fibre("twine"))
        loop["bbd_uv"] = "src"
        objs.append(loop)
    return {"objects": objs, "markers": {},
            "report": {"notes": "Origin at the bottom centre, bundle lies along X."}}


def build_ammo_shells():
    """Burlap drawstring pouch spilling chunky carrot pellets."""
    m = M()
    objs = []

    def wrinkle(i, j, a, t, r):
        return r * (1.0 + 0.045 * math.sin(9 * a + t * 40) * min(1.0, t / 0.05))
    sack = [(0.0, 0.0), (0.004, 0.055), (0.02, 0.085), (0.06, 0.098), (0.11, 0.094), (0.15, 0.078), (0.17, 0.064),
            (0.18, 0.060), (0.195, 0.070), (0.215, 0.088), (0.222, 0.092), (0.220, 0.086), (0.200, 0.070)]
    pouch = geo.lathe("pouch", sack, segs=28, mat=m["burlap"], axis="Z", cap1=False, radius_fn=wrinkle,
                      sharp_angle=None)
    geo.displace_noise(pouch, 0.004, 25.0, seed=3)
    objs.append(pouch)
    objs.append(parts.twine_sleeve("drawstring", (0, 0, 0.178), (0, 0, 1), 0.060, 0.008, rings=1))
    objs += parts.knot("draw_knot", (0.0, -0.064, 0.178), 0.008, seed=6, tail_dir=(0.2, -0.5, -1.0))
    # carrot chunks heaped in the mouth and spilled in front
    rng = random.Random(9)
    spots = [(0.0, 0.0, 0.205), (0.03, 0.02, 0.198), (-0.03, 0.015, 0.2), (0.015, -0.03, 0.2), (-0.02, -0.025, 0.196),
             (0.0, 0.03, 0.215), (0.07, -0.11, 0.012), (0.0, -0.13, 0.012), (-0.06, -0.12, 0.016)]
    for k, p in enumerate(spots):
        spec = build_carrot_shell_pellet()
        o = spec["objects"][0]
        o.name = f"chunk{k}"
        o.location = p
        o.rotation_euler = (rng.uniform(-1.2, 1.2), rng.uniform(0, 6.28), rng.uniform(-1.2, 1.2)) if k < 6 else \
            (math.radians(90) + rng.uniform(-0.3, 0.3), 0.0, rng.uniform(0, 6.28))
        objs.append(o)
    return {"objects": objs, "markers": {},
            "report": {"notes": "Origin at the bottom centre."}}


def build_ammo_heavy():
    """Galvanised tin drum with a leather belt of strapped carrots spilling out."""
    m = M()
    objs = []
    can = [(0.0, 0.0), (0.0, 0.092), (0.004, 0.098), (0.010, 0.100), (0.055, 0.100), (0.058, 0.104), (0.062, 0.100),
           (0.120, 0.100), (0.123, 0.104), (0.127, 0.100), (0.172, 0.100), (0.176, 0.103), (0.180, 0.100),
           (0.180, 0.0)]
    drum = geo.lathe("drum", can, segs=32, mat=m["orange"], axis="Z", sharp_angle=50)
    objs.append(drum)
    lid = geo.lathe("lid", [(0.178, 0.104), (0.186, 0.104), (0.190, 0.098), (0.192, 0.07), (0.196, 0.03),
                            (0.198, 0.0)], segs=32, mat=m["sage"], axis="Z", cap1=True, sharp_angle=50)
    objs.append(lid)
    # wire bail handle
    bail = [Vector((0.101 * math.cos(a), 0.0, 0.16 + 0.07 * math.sin(a))) for a in
            [math.radians(d) for d in range(0, 181, 15)]]
    objs.append(geo.sweep("bail", bail, 0.0028, segs=6, mat=m["iron"]))
    for sx in (1, -1):
        objs.append(parts.rivet(f"bail_ear{sx}", (sx * 0.101, 0.0, 0.16), (sx, 0, 0), 0.008, m["iron"]))
    # belt: leather strip out of a slot in the side, down to the ground, carrots strapped across it
    path = [Vector((0.0, -0.100, 0.14)), Vector((0.0, -0.115, 0.13)), Vector((0.01, -0.14, 0.09)),
            Vector((0.02, -0.16, 0.04)), Vector((0.03, -0.19, 0.012)), Vector((0.05, -0.25, 0.008)),
            Vector((0.08, -0.31, 0.008))]
    belt = geo.sweep("belt", path, 0.022, segs=8, mat=m["leather"], flatten=0.15, up=(0, -0.3, 1))
    objs.append(belt)
    objs.append(geo.box("slot", (0.06, 0.012, 0.014), (0.0, -0.098, 0.142), m["iron"], bevel=0.002))
    acc = [0.0]
    for a, b in zip(path, path[1:]):
        acc.append(acc[-1] + (b - a).length)
    k = 0
    s = 0.03
    while s < acc[-1] - 0.01:
        i = max(j for j in range(len(acc) - 1) if acc[j] <= s)
        f = (s - acc[i]) / (acc[i + 1] - acc[i])
        p = path[i].lerp(path[i + 1], f)
        t = (path[i + 1] - path[i]).normalized()
        side = t.cross(Vector((0, 0, 1))).normalized()
        nrm = side.cross(t).normalized()
        if nrm.z < 0:
            nrm = -nrm
        objs += baby_carrot(f"belt_c{k}", 0.075, 0.0105, pos=p + nrm * 0.011 - side * 0.0375, axis=-side, seed=90 + k,
                            tops=False, segs=8)
        clip = geo.sweep(f"clip{k}", [p + nrm * 0.004 - t * 0.0125, p + nrm * 0.02 - t * 0.008,
                                      p + nrm * 0.024, p + nrm * 0.02 + t * 0.008, p + nrm * 0.004 + t * 0.0125],
                         0.0045, segs=5, mat=m["brass"], flatten=0.3)
        objs.append(clip)
        k += 1
        s += 0.034
    return {"objects": objs, "markers": {},
            "report": {"notes": "Origin at the bottom centre of the drum; the belt spills toward +Z (front)."}}


def build_ammo_rocket():
    """Two rocket carrots strapped side by side onto a notched pine cradle."""
    m = M()
    objs = []
    for k, sx in enumerate((1, -1)):
        rp, L = carrot_rocket_parts(scale=0.85, fin_spread=0.25)
        xf = Matrix.Translation((0.0, sx * 0.048, 0.072)) @ Matrix.Rotation(math.radians(-90), 4, "Z")
        bpy.context.view_layer.update()   # make matrix_world reflect orient()'s loc/rot first
        for o in rp:
            o.name = f"r{k}_{o.name}"
            o.matrix_world = xf @ o.matrix_world      # lie along X, tips toward +X
        objs += rp
    for x in (-0.12, 0.10):
        cr_o = [(-0.105, 0.0), (0.105, 0.0), (0.105, 0.05), (0.09, 0.058), (0.084, 0.045)]
        for k in range(1, 12):
            a = math.pi * k / 12
            cr_o.append((0.048 + 0.041 * math.cos(a), 0.072 - 0.041 * math.sin(a)))
        cr_o += [(0.0, 0.058)]
        for k in range(1, 12):
            a = math.pi * k / 12
            cr_o.append((-0.048 + 0.041 * math.cos(a), 0.072 - 0.041 * math.sin(a)))
        cr_o += [(-0.084, 0.045), (-0.09, 0.058), (-0.105, 0.05)]
        board = geo.extrude_outline(f"cradle{x}", cr_o, 0.026, m["pine"], plane="YZ", bevel=0.003, bevel_segs=1)
        board.location = (x, 0, 0)
        objs.append(board)
        objs.append(parts.twine_sleeve(f"strap{x}", (x + 0.02, 0.0, 0.072), (1, 0, 0), 0.062, 0.012, rings=1))
    rail = geo.box("rail", (0.30, 0.03, 0.016), (-0.01, 0.0, 0.008), m["pine_box"], bevel=0.003)
    objs.append(rail)
    return {"objects": objs, "markers": {},
            "report": {"notes": "Origin at the bottom centre; rockets point along +X."}}


# --------------------------------------------------------------------------- crates

CW, CD, CH = 0.80, 0.52, 0.44     # crate body width (x), depth (y), height (z)


def crate(variant="loot"):
    """Garden crate body + lid parts. Returns (body_objs, lid_objs, lid_pivot)."""
    m = M()
    stencil = textures.stencil_carrot()
    paint_hex = "#e8741c" if variant == "loot" else "#f2ead8"
    face = mats.stencil_wood(f"crate_stencil_{variant}", stencil, ph="rough_wood", tint="#d8c3a2" if variant == "loot"
                             else "#c9b08c", paint_hex=paint_hex, proj="XZ", center=(0.0, 0.225), size=0.36)
    wood = m["crate"]
    body, lid = [], []
    t = 0.018
    # corner posts
    for sx in (1, -1):
        for sy in (1, -1):
            body.append(geo.box(f"post{sx}{sy}", (0.045, 0.045, CH), (sx * (CW / 2 - t - 0.0225),
                                                                       sy * (CD / 2 - t - 0.0225), CH / 2),
                                wood, bevel=0.003))
    # slats
    sh, gap = 0.12, 0.028
    for i in range(3):
        z = 0.015 + i * (sh + gap) + sh / 2
        for sy in (1, -1):
            body.append(geo.box(f"slat_fb{i}{sy}", (CW, t, sh), (0, sy * (CD / 2 - t / 2), z), face, bevel=0.003))
        for sx in (1, -1):
            body.append(geo.box(f"slat_end{i}{sx}", (t, CD - 2 * t, sh), (sx * (CW / 2 - t / 2), 0, z), wood,
                                bevel=0.003))
    for k in range(4):
        body.append(geo.box(f"floor{k}", (CW - 2 * t, (CD - 2 * t) / 4 - 0.006, 0.016),
                            (0, -CD / 2 + t + (k + 0.5) * (CD - 2 * t) / 4, 0.008), wood, bevel=0.002))
    # iron corner brackets
    for sx in (1, -1):
        for sy in (1, -1):
            for z in (0.03, CH - 0.03):
                body.append(geo.box(f"brk_a{sx}{sy}{z}", (0.07, 0.004, 0.05), (sx * (CW / 2 - 0.035),
                                                                               sy * (CD / 2 + 0.002), z),
                                    m["iron"], bevel=0.0012))
                body.append(geo.box(f"brk_b{sx}{sy}{z}", (0.004, 0.07, 0.05), (sx * (CW / 2 + 0.002),
                                                                               sy * (CD / 2 - 0.035), z),
                                    m["iron"], bevel=0.0012))
    # rope handles on the ends
    for sx in (1, -1):
        arc = [Vector((sx * (CW / 2 + 0.012), -0.075 + 0.15 * q, 0.30 - 0.06 * math.sin(math.pi * q)))
               for q in [k / 10 for k in range(11)]]
        h = geo.sweep(f"handle{sx}", arc, 0.007, segs=6, mat=mats.fibre("rope", tint="#b8925a", ply=3, twist=60))
        h["bbd_uv"] = "src"
        body.append(h)
        for y in (-0.075, 0.075):
            body += parts.knot(f"hk{sx}{y}", (sx * (CW / 2 + 0.012), y, 0.30), 0.011, seed=int(y * 100) + sx,
                               tails=False)
    if variant == "supply":  # two orange-painted iron bands round the body
        for x in (-0.24, 0.24):
            for sy in (1, -1):
                body.append(geo.box(f"band{x}{sy}", (0.05, 0.005, CH - 0.01), (x, sy * (CD / 2 + 0.0035), CH / 2),
                                    m["orange"], bevel=0.0015))
            body.append(geo.box(f"band_bot{x}", (0.05, CD + 0.012, 0.005), (x, 0, -0.002), m["orange"], bevel=0.0015))
    # contents (visible when the lid is open): burlap bedding + a few carrots
    bed = geo.box("bedding", (CW - 2 * t - 0.02, CD - 2 * t - 0.02, 0.24), (0, 0, 0.14), m["burlap"], bevel=0.03,
                  segs=3)
    geo.displace_noise(bed, 0.012, 12.0, seed=2)
    body.append(bed)
    for k, (x, y, a) in enumerate(((-0.18, -0.05, 20), (0.0, 0.06, -15), (0.17, -0.02, 35))):
        cs = baby_carrot(f"loot_carrot{k}", 0.22, 0.022, pos=(x + 0.1 * math.cos(math.radians(a)),
                                                              y + 0.1 * math.sin(math.radians(a)), 0.285),
                         axis=(math.cos(math.radians(a)), math.sin(math.radians(a)), -0.08), seed=110 + k)
        body += cs
    # back hinge knuckles + lid
    hinge_y, hinge_z = CD / 2, CH + 0.004
    for x in (-0.25, 0.25):
        body.append(geo.box(f"hinge_back{x}", (0.05, 0.004, 0.09), (x, CD / 2 + 0.003, CH - 0.045), m["iron"],
                            bevel=0.0012))
        body.append(geo.cylinder(f"knuckle{x}", 0.007, 0.05, 10, m["iron"], axis="X", bevel=0.0015))
        body[-1].location = (x, hinge_y + 0.003, hinge_z)
        lid.append(geo.box(f"hinge_strap{x}", (0.045, 0.16, 0.004), (x, CD / 2 - 0.08, CH + 0.024), m["iron"],
                           bevel=0.0012))
    pw = CD / 4
    for k in range(4):
        lid.append(geo.box(f"lid_plank{k}", (CW, pw - 0.005, 0.02), (0, -CD / 2 + (k + 0.5) * pw, CH + 0.012),
                           wood if variant == "loot" else m["crate"], bevel=0.003))
    for x in (-0.31, 0.31):
        lid.append(geo.box(f"batten{x}", (0.06, CD - 0.02, 0.022), (x, 0, CH + 0.033), m["pine_box"], bevel=0.004))
    brace = geo.box("brace", (0.06, math.hypot(0.56, CD - 0.08), 0.02), (0, 0, CH + 0.032), m["pine_box"], bevel=0.004)
    brace.rotation_euler = (0, 0, -math.atan2(0.56, CD - 0.08))
    lid.append(brace)
    # hasp on the lid front + staple on the front slat
    lid.append(geo.box("hasp", (0.035, 0.004, 0.07), (0, -CD / 2 - 0.004, CH - 0.012), m["iron"], bevel=0.0012))
    body.append(geo.sweep("staple", [Vector((-0.008, -CD / 2 - 0.002, CH - 0.06)), Vector((-0.008, -CD / 2 - 0.016, CH - 0.06)),
                                     Vector((0.008, -CD / 2 - 0.016, CH - 0.06)), Vector((0.008, -CD / 2 - 0.002, CH - 0.06))],
                          0.003, segs=6, mat=m["iron"]))
    tag(lid, "Lid")
    return body, lid, (0.0, hinge_y + 0.003, hinge_z)


def build_loot_crate():
    body, lid, pivot = crate("loot")
    return {"objects": body + lid, "pivots": {"Lid": pivot}, "markers": {},
            "report": {"notes": "Origin at the bottom centre, front (stencilled carrot) faces +Z. `Lid` pivots on "
                                "the back hinge line: rotate Lid.rotation.x towards -110 deg to open."}}


def chute(base_z, radius, seed=3):
    """Dandelion-seed parachute above a load whose top is at base_z: lines -> seed -> beak -> pappus."""
    m = M()
    objs = []
    seed_z = base_z + 0.70
    seed_len = 0.20
    objs.append(plants.achene("seed", (0, 0, seed_z), seed_len, 0.038, seed=seed))
    top = seed_z + seed_len
    pz = top + 0.95
    objs.append(plants.beak("beak", (0, 0, top - 0.01), (0, 0, pz), 0.009))
    objs.append(geo.lathe("pappus_knot", [(pz - 0.02, 0.0), (pz - 0.015, 0.03), (pz + 0.01, 0.04),
                                          (pz + 0.03, 0.02), (pz + 0.035, 0.0)], segs=12,
                          mat=mats.plain("pappus_knot", "#efe9da", rough=0.8, noise_amt=0.1, sheen=0.6), axis="Z"))
    objs.append(plants.pappus("pappus", (0, 0, pz), radius, n=130, seed=seed))
    for sx in (1, -1):
        for sy in (1, -1):
            a = Vector((sx * (CW / 2 - 0.04), sy * (CD / 2 - 0.04), base_z + 0.045))
            b = Vector((0, 0, seed_z + 0.01))
            line = geo.sweep(f"line{sx}{sy}", [a.lerp(b, q) for q in (0, 0.5, 1)], 0.0045, segs=5,
                             mat=mats.fibre("twine"))
            line["bbd_uv"] = "src"
            objs.append(line)
    objs += parts.knot("line_knot", (0, 0, seed_z + 0.005), 0.016, seed=4, tails=False)
    return tag(objs, "Chute"), pz


def build_supply_drop():
    body, lid, pivot = crate("supply")
    chute_objs, pz = chute(CH + 0.05, 1.15)
    return {"objects": body + lid + chute_objs,
            "pivots": {"Lid": pivot, "Chute": (0.0, 0.0, CH + 0.05)},
            "markers": {},
            "report": {"notes": "Crate + `Lid` (as loot_crate) under a dandelion-seed parachute `Chute` "
                                "(pivot at the crate top; hide or detach it on landing). Pappus bristles use an "
                                "alpha-scissor texture (second material)."}}


def build_dandelion_glider():
    """A single giant dandelion seed: hold the seed handle, the pappus parachute floats overhead."""
    m = M()
    objs = []
    objs.append(plants.achene("handle_seed", (0, 0, -0.085), 0.20, 0.026, seed=5))
    objs.append(parts.twine_sleeve("grip_wrap", (0, 0, 0.0), (0, 0, 1), 0.026, 0.07, rings=3))
    objs.append(plants.beak("beak", (0, 0, 0.10), (0, 0, 0.62), 0.0075))
    objs.append(geo.lathe("pappus_knot", [(0.60, 0.0), (0.605, 0.022), (0.625, 0.028), (0.64, 0.014), (0.645, 0.0)],
                          segs=12, mat=mats.plain("pappus_knot", "#efe9da", rough=0.8, noise_amt=0.1, sheen=0.6),
                          axis="Z"))
    objs.append(plants.pappus("pappus", (0, 0, 0.625), 0.60, n=110, seed=7))
    return {"objects": objs,
            "markers": {"Hand_L": (0.0, 0.0, 0.035), "Hand_R": (0.0, 0.0, -0.035)},
            "report": {"notes": "Origin at the hand grip (centre of the twine wrap). Hand_L / Hand_R are IK "
                                "targets above/below it. Pappus is ~1.2 m wide, centre 0.63 m above the grip."}}


ASSETS = {
    "pickup_health": dict(build=build_pickup_health, out="props", tex=1024, kind="pickup", target=0.3,
                          use="Health pickup: dandelion-tea flask with a four-leaf clover"),
    "pickup_armor": dict(build=build_pickup_armor, out="props", tex=1024, kind="pickup", target=0.42,
                         use="Armour pickup: pine-bark breastplate with an acorn-shell boss"),
    "ammo_light": dict(build=build_ammo_light, out="props", tex=512, kind="pickup", target=0.25,
                       use="Light ammo (pistol / LMG bolts): bundle of carrots tied with twine"),
    "ammo_shells": dict(build=build_ammo_shells, out="props", tex=512, kind="pickup", target=0.25,
                        use="Shotgun ammo: burlap pouch of carrot chunks"),
    "ammo_heavy": dict(build=build_ammo_heavy, out="props", tex=1024, kind="pickup", target=0.35,
                       use="Heavy ammo (LMG): tin drum with a belt of strapped carrots"),
    "ammo_rocket": dict(build=build_ammo_rocket, out="props", tex=512, kind="pickup", target=0.42,
                        use="Rocket ammo: two rocket carrots on a pine cradle"),
    "loot_crate": dict(build=build_loot_crate, out="props", tex=1024, kind="prop", target=0.8,
                       use="Lootable garden crate with an opening Lid"),
    "supply_drop": dict(build=build_supply_drop, out="props", tex=1024, kind="prop", target=2.6,
                        use="Air-dropped supply crate under a dandelion-seed parachute (Chute)"),
    "dandelion_glider": dict(build=build_dandelion_glider, out="props", tex=512, kind="prop", target=1.2,
                             use="Glider for the battle-royale drop: a giant dandelion seed held overhead"),
}
