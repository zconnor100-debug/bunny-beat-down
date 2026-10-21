"""Treasure chests: a banded oak chest and a rarer gilded one.

Both share one parametric build: a planked body on a plinth, a barrel-vault lid
of seven staves between two end caps, iron/gold bands over body and lid, brass
or gold corner caps, ring handles, back hinges and a carrot-shaped hasp with a
keyhole and leafy top. The oak chest has carved oak leaves and acorns on the
lid; the golden chest is gold-leafed oak with acorn-cupule embossing on the lid
staves and acorn medallions.

Blender space: front faces -Y (glTF +Z), origin at the bottom centre. The lid
is the separate node `Lid` pivoting on the back hinge line (rotate its X
towards -110 deg to open); `LootSpawn` sits just above the open box.
"""
from __future__ import annotations

import math

from mathutils import Matrix, Vector

from bbd import geo, mats, parts

W, D, H = 0.90, 0.56, 0.40       # body width (x), depth (y), height (z)
LH = 0.235                       # lid arch rise
T = 0.024                        # plank thickness
STAVES = 7
BANDS_X = (-0.30, 0.30)


def box(*a, segs=1, **k):
    """Chest boxes use single-segment bevels (many small parts, tight triangle budget)."""
    return geo.box(*a, segs=segs, **k)


def arch(theta, off=0.0):
    """Point on the lid's elliptical arch (theta 0 = front edge, pi = back edge) + outward offset."""
    a, b = D / 2, LH
    y, z = -a * math.cos(theta), b * math.sin(theta)
    n = Vector((y / (a * a), z / (b * b))).normalized()
    return Vector((y + n.x * off, H + z + n.y * off)), n


def oak_leaf_outline(length, width, lobes=4, n=12):
    """Lobed oak leaf in plane coords (a along the midrib from 0 to length, b across)."""
    right, left = [], []
    for k in range(n + 1):
        t = k / n
        w = width * 0.5 * math.sin(math.pi * min(1.0, t * 1.05)) ** 0.75 \
            * (0.72 + 0.28 * math.cos(2 * math.pi * lobes * t))
        right.append((t * length, w))
        left.append((t * length, -w))
    pts = [(0.0, 0.0)] + right[1:-1] + [(length, 0.0)] + list(reversed(left[1:-1]))
    return pts


def carrot_outline(top_w, length, n=14):
    """Front-view carrot pointing down (crown at b = 0, tip at b = -length)."""
    right = []
    for k in range(n + 1):
        t = k / n
        w = top_w * 0.5 * (1 - t) ** 0.85 * (1.0 if t > 0.12 else math.sqrt(max(0.0, 1 - ((0.12 - t) / 0.12) ** 2 * 0.35)))
        right.append((max(w, 0.004 * (1 - t)), -t * length))
    pts = [(0.0, 0.006)] + right + [(-x, y) for x, y in reversed(right)]
    return pts


def acorn_relief(name, pos, normal_axis, size, nut_mat, cap_mat, flat=0.5):
    """Small acorn (nut + scaly cap + stem) flattened against a panel (bas-relief)."""
    nut = geo.lathe(f"{name}_nut", [(0.0, 0.0), (size * 0.15, size * 0.32), (size * 0.5, size * 0.42),
                                    (size * 0.8, size * 0.38), (size * 0.9, size * 0.30)], segs=14, mat=nut_mat,
                    axis="Z", cap1=True, sharp_angle=None)
    cap = geo.lathe(f"{name}_cap", [(size * 0.78, size * 0.36), (size * 0.84, size * 0.47), (size * 0.98, size * 0.45),
                                    (size * 1.08, size * 0.30), (size * 1.12, 0.0)], segs=14, mat=cap_mat, axis="Z",
                    sharp_angle=None)
    stem = geo.cylinder(f"{name}_stem", size * 0.06, size * 0.18, 6, cap_mat, axis="Z", center=False)
    stem.location = (0, 0, size * 1.08)
    out = []
    for o in (nut, cap, stem):
        sc = [1.0, 1.0, 1.0]
        sc["XYZ".index(normal_axis)] = flat
        o.scale = sc
        o.location = Vector(pos) + Vector(o.location) * 1.0
        o["bbd_uv"] = "smart"
        out.append(o)
    return out


def build_chest(variant="oak"):
    golden = variant == "golden"
    if golden:
        m = {"plank": mats.gilded("chest_gilt"), "lid": mats.emboss_scales("lid_cupule_emboss"),
             "band": mats.metal("chest_gold", "gold", wear=0.6), "corner": mats.metal("chest_gold", "gold"),
             "lock": mats.metal("lock_gold", "gold", wear=0.8, rough=0.14),
             "leafy": mats.plain("green_enamel", "#2f7a3a", rough=0.12, coat=1.0, noise_amt=0.05),
             "lining": mats.velvet("velvet_blue", "#22306e"),
             "carve_nut": mats.metal("gold_polished", "gold", rough=0.12),
             "carve_cap": mats.emboss_scales("acorn_cap_emboss", cell=0.008)}
    else:
        m = {"plank": mats.wood("chest_oak", "oak_veneer_01", coords="box", tint="#b9875c", rough=0.5, wear=0.45,
                                dirt=0.5),
             "band": mats.metal("chest_iron", "iron", wear=0.5), "corner": mats.metal("brass", "brass", wear=0.6),
             "lock": mats.metal("lock_brass", "brass", wear=0.8, rough=0.18),
             "leafy": mats.metal("lock_brass", "brass", wear=0.8, rough=0.18),
             "lining": mats.velvet("velvet_red", "#7d1622"),
             "carve_nut": mats.wood("chest_oak", "oak_veneer_01"), "carve_cap": mats.wood("chest_oak", "oak_veneer_01")}
        m["lid"] = m["plank"]
    body, lid = [], []

    # ---- body: plinth, planked walls, velvet lining --------------------------------------------
    body.append(box("plinth", (W + 0.03, D + 0.03, 0.045), (0, 0, 0.0225), m["plank"], bevel=0.006))
    ph = (H - 0.045) / 3
    for i in range(3):
        z = 0.045 + (i + 0.5) * ph
        for sy in (1, -1):
            body.append(box(f"plank_fb{i}{sy}", (W, T, ph - 0.002), (0, sy * (D / 2 - T / 2), z), m["plank"],
                                bevel=0.004))
        for sx in (1, -1):
            body.append(box(f"plank_end{i}{sx}", (T, D - 2 * T, ph - 0.002), (sx * (W / 2 - T / 2), 0, z),
                                m["plank"], bevel=0.004))
    body.append(box("lining_floor", (W - 2 * T - 0.01, D - 2 * T - 0.01, 0.02), (0, 0, 0.06), m["lining"],
                        bevel=0.006))
    for sy in (1, -1):
        body.append(box(f"lining_fb{sy}", (W - 2 * T - 0.01, 0.012, H - 0.09), (0, sy * (D / 2 - T - 0.006),
                                                                                    0.06 + (H - 0.09) / 2),
                            m["lining"], bevel=0.004))
    for sx in (1, -1):
        body.append(box(f"lining_end{sx}", (0.012, D - 2 * T - 0.03, H - 0.09),
                            (sx * (W / 2 - T - 0.006), 0, 0.06 + (H - 0.09) / 2), m["lining"], bevel=0.004))
    # ---- bands, corners, handles, hinges -------------------------------------------------------------
    for bx in BANDS_X:
        for sy in (1, -1):
            body.append(box(f"band{bx}{sy}", (0.046, 0.007, H - 0.045), (bx, sy * (D / 2 + 0.0035),
                                                                             0.045 + (H - 0.045) / 2),
                                m["band"], bevel=0.0015))
            body.append(box(f"band_plinth{bx}{sy}", (0.046, 0.007, 0.045), (bx, sy * (D / 2 + 0.0185), 0.0225),
                                m["band"], bevel=0.0015))
            for z in (0.11, 0.23, 0.35):
                body.append(parts.rivet(f"band_rv{bx}{sy}{z}", (bx, sy * (D / 2 + 0.007), z), (0, sy, 0), 0.0065,
                                        m["corner"], segs=6))
    for sx in (1, -1):
        for sy in (1, -1):
            for z in (0.08, H - 0.035):
                body.append(box(f"cnr_a{sx}{sy}{z}", (0.075, 0.005, 0.07), (sx * (W / 2 - 0.0375), sy * (D / 2 + 0.003), z),
                                    m["corner"], bevel=0.0015))
                body.append(box(f"cnr_b{sx}{sy}{z}", (0.005, 0.075, 0.07), (sx * (W / 2 + 0.003), sy * (D / 2 - 0.0375), z),
                                    m["corner"], bevel=0.0015))
        # side ring handle
        body.append(box(f"handle_mount{sx}", (0.012, 0.07, 0.035), (sx * (W / 2 + 0.006), 0, 0.29), m["band"],
                            bevel=0.003))
        ring = geo.sweep(f"handle_ring{sx}", [Vector((sx * (W / 2 + 0.018), 0.05 * math.cos(a), 0.29 - 0.05 * math.sin(a)))
                                              for a in [math.pi * k / 10 for k in range(11)]], 0.007, segs=6,
                         mat=m["band"])
        body.append(ring)
    hinge_y, hinge_z = D / 2 + 0.008, H + 0.002
    for hx in (-0.24, 0.24):
        body.append(box(f"hinge_plate{hx}", (0.05, 0.006, 0.08), (hx, D / 2 + 0.003, H - 0.045), m["band"],
                            bevel=0.0015))
        kn = geo.cylinder(f"hinge_knuckle{hx}", 0.009, 0.06, 8, m["band"], axis="X", bevel=0.002)
        kn.location = (hx, hinge_y, hinge_z)
        body.append(kn)

    # ---- lid: staves between end caps, bands, corner caps, hinge straps --------------------------------
    for k in range(STAVES):
        t0, t1 = math.pi * k / STAVES, math.pi * (k + 1) / STAVES
        (o0, n0), (o1, n1) = arch(t0), arch(t1)
        i0, i1 = o0 - n0 * T, o1 - n1 * T
        st = geo.extrude_outline(f"stave{k}", [tuple(o0), tuple(o1), tuple(i1), tuple(i0)], W, m["lid"],
                                 bevel=0.004, bevel_segs=1)
        lid.append(st)
    cap_pts = [tuple(arch(math.pi * k / 14, -0.002)[0]) for k in range(15)]
    for sx in (1, -1):
        cap = geo.extrude_outline(f"end_cap{sx}", cap_pts, T, m["plank"], offset=sx * (W / 2 - T / 2 - 0.001),
                                  bevel=0.004, bevel_segs=1)
        lid.append(cap)
    for bx in BANDS_X:
        pts = [arch(math.pi * k / 16, 0.004)[0] for k in range(17)]
        band = geo.sweep(f"lid_band{bx}", [Vector((bx, p.x, p.y)) for p in pts], 0.023, segs=4, mat=m["band"],
                         flatten=0.15, up=(0, -1, 0))
        lid.append(band)
        for th in (0.35, 1.05, 2.1, 2.8):
            p, n = arch(th, 0.007)
            lid.append(parts.rivet(f"lid_rv{bx}{th}", (bx, p.x, p.y), (0, n.x, n.y), 0.0065, m["corner"], segs=6))
    for sx in (1, -1):
        for th in (0.0, math.pi):
            p, n = arch(th + (0.18 if th == 0 else -0.18), 0.003)
            lid.append(box(f"lid_cnr{sx}{th}", (0.07, 0.006, 0.06), (sx * (W / 2 - 0.035), p.x, H + 0.035),
                               m["corner"], bevel=0.0015))
            lid.append(box(f"lid_cnr_end{sx}{th}", (0.006, 0.07, 0.06),
                               (sx * (W / 2 + 0.002), (D / 2 - 0.035) * (1 if th else -1), H + 0.035), m["corner"],
                               bevel=0.0015))
    for hx in (-0.24, 0.24):
        pts = [arch(math.pi - math.radians(a), 0.004)[0] for a in range(0, 46, 9)]
        lid.append(geo.sweep(f"hinge_strap{hx}", [Vector((hx, p.x, p.y)) for p in pts], 0.022, segs=6, mat=m["band"],
                             flatten=0.16, up=(0, 1, 0)))

    # ---- carrot hasp with keyhole and a leafy top (on the lid front, hanging over the body) ----------
    hz = H + 0.035
    hasp = geo.extrude_outline("hasp", carrot_outline(0.095, 0.20, n=10), 0.014, m["lock"], plane="XZ",
                               bevel=0.003, bevel_segs=1)
    hasp.location = (0, -D / 2 - 0.016, hz)
    lid.append(hasp)
    for k in range(3):   # ring grooves of the carrot, as raised bands
        z = hz - 0.04 - k * 0.04
        w = 0.095 * 0.5 * (1 - (0.04 + k * 0.04) / 0.20) ** 0.85
        lid.append(box(f"hasp_ring{k}", (w * 1.6, 0.004, 0.005), (0, -D / 2 - 0.024, z), m["lock"], bevel=0.0015,
                           segs=1))
    kh = [(0.0, 0.012)] + [(0.009 * math.cos(math.radians(a)), 0.009 * math.sin(math.radians(a)) + 0.004)
                           for a in range(-40, 225, 25)] + [(-0.004, -0.014), (0.004, -0.014)]
    key = geo.extrude_outline("keyhole", kh, 0.004, mats.metal("blued", "blued"), plane="XZ",
                              bevel=0.0008, bevel_segs=1)
    key.location = (0, -D / 2 - 0.0255, hz - 0.085)
    lid.append(key)
    for k, ang in enumerate((-38, 0, 38)):
        lo = oak_leaf_outline(0.085 if ang == 0 else 0.07, 0.036, lobes=3, n=10)
        leaf = geo.extrude_outline(f"hasp_leaf{k}", [(b, a) for a, b in lo], 0.005, m["leafy"],
                                   plane="XZ", bevel=0.0015, bevel_segs=1)
        leaf.matrix_world = (Matrix.Translation((0, -D / 2 - 0.006, hz + 0.004)) @ Matrix.Rotation(math.radians(-20), 4, "X")
                             @ Matrix.Rotation(math.radians(ang), 4, "Y"))
        lid.append(leaf)

    # ---- carving / embossing -------------------------------------------------------------------------
    for sx in (1, -1):
        x = sx * (W / 2 + 0.003)
        if golden:
            med = geo.cylinder(f"end_medallion{sx}", 0.075, 0.008, 20, m["band"], axis="X", bevel=0.003)
            med.location = (x + sx * 0.002, 0.0, H + 0.105)
            lid.append(med)
            lid += acorn_relief(f"end_acorn{sx}", (x + sx * 0.008, 0.0, H + 0.058), "X", 0.075, m["carve_nut"],
                                m["carve_cap"], flat=0.45)
        else:
            for k, (dy, rot) in enumerate(((-0.07, 25), (0.07, -25))):
                lo = oak_leaf_outline(0.15, 0.075, lobes=4)
                leaf = geo.extrude_outline(f"carved_leaf{sx}{k}", [(b, a) for a, b in lo], 0.008,
                                           m["plank"], plane="YZ", offset=0.0, bevel=0.002, bevel_segs=1)
                leaf.rotation_euler = (math.radians(rot), 0.0, 0.0)
                leaf.location = (x + sx * 0.002, dy, H + 0.03)
                lid.append(leaf)
            lid += acorn_relief(f"carved_acorn{sx}", (x + sx * 0.006, 0.0, H + 0.04), "X", 0.05, m["plank"],
                                m["plank"], flat=0.45)
    if golden:
        for k, mx in enumerate((-0.165, 0.165)):
            med = geo.cylinder(f"front_medallion{k}", 0.058, 0.008, 18, m["band"], axis="Y", bevel=0.003)
            med.location = (mx, -D / 2 - 0.006, 0.22)
            body.append(med)
            body += acorn_relief(f"front_acorn{k}", (mx, -D / 2 - 0.012, 0.18), "Y", 0.06, m["carve_nut"],
                                 m["carve_cap"], flat=0.45)
    else:
        for k, (mx, rot) in enumerate(((-0.16, 70), (0.16, -70))):
            p, n = arch(0.62, 0.002)
            lo = oak_leaf_outline(0.13, 0.065, lobes=4)
            leaf = geo.extrude_outline(f"lid_leaf{k}", lo, 0.007, m["plank"], plane="XZ",
                                       bevel=0.002, bevel_segs=1)
            # fan the leaf in its own plane, then tilt its face (-Y) onto the lid normal
            tilt = math.atan2(-n.y, -n.x)
            leaf.matrix_world = (Matrix.Translation((mx, p.x - 0.002, p.y)) @ Matrix.Rotation(tilt, 4, "X")
                                 @ Matrix.Rotation(math.radians(rot), 4, "Y"))
            lid.append(leaf)

    for o in lid:
        o["bbd_node"] = "Lid"
    name = "treasure_chest_golden" if golden else "treasure_chest"
    return {"objects": body + lid, "pivots": {"Lid": (0.0, hinge_y, hinge_z)},
            "markers": {"LootSpawn": (0.0, 0.0, H + 0.06)},
            "report": {"notes": "Origin at the bottom centre, front faces +Z. `Lid` pivots on the back hinge line "
                                "(rotate its X towards -110 deg to open). `LootSpawn` is centred just above the "
                                "open box."}}


def build_treasure_chest():
    return build_chest("oak")


def build_treasure_chest_golden():
    return build_chest("golden")


ASSETS = {
    "treasure_chest": dict(build=build_treasure_chest, out="props", tex=1024, kind="prop", target=0.9, capsule=1.1,
                           use="Treasure chest (better loot, slow 5 s open): banded oak, carrot hasp, carved lid"),
    "treasure_chest_golden": dict(build=build_treasure_chest_golden, out="props", tex=1024, kind="prop", target=0.9,
                                  capsule=1.1,
                                  use="Rare golden treasure chest: gilded oak, acorn-cap embossing and medallions"),
}
