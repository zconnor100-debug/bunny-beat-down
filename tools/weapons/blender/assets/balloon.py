"""Dropship balloon: the battle-royale "battle bus".

A patchwork hot-air balloon (gores and bands sewn from six real fabric scans:
orange wool, red picnic check, green gingham, yellow waffle cotton, leaf-green
poplin, cream windowpane plaid) with a giant sprig of carrot greens on the
crown, carrying a woven wicker PICNIC BASKET big enough for ~24 critters: open
gingham-lined lids, leather straps, burlap sandbags, a brass burner on garden
canes and rope rigging.

Blender space: origin at the centre of the basket floor, +Z up, flying toward
+Y (exported as glTF/Godot -Z). Envelope ~14 m tall, basket 4 m x 3 m.
"""
from __future__ import annotations

import math
import random

import bmesh
from mathutils import Vector

from bbd import geo, mats, parts

BW, BD, BH = 4.0, 3.0, 0.78      # basket outer width (x), depth (y), wall height
CORNER = 0.42
WALL = 0.12
FABRICS = [("caban", "#ffffff"), ("fabric_pattern_07", "#ffffff"), ("gingham_check", "#ffffff"),
           ("waffle_pique_cotton", "#ffffff"), ("stretch_poplin", "#ffffff"), ("fabric_pattern_05", "#ffffff")]
GORES = 24
ENVELOPE = [  # (z, r): inverted teardrop, widest high up, long taper to the throat
    (4.20, 1.62), (4.55, 1.45), (4.85, 1.38), (5.50, 1.85), (6.40, 2.55), (7.50, 3.35), (8.80, 4.20),
    (10.20, 5.00), (11.70, 5.65), (13.20, 6.10), (14.50, 6.25), (15.70, 5.95), (16.80, 5.15),
    (17.70, 4.05), (18.40, 2.75), (18.85, 1.45), (19.02, 0.55), (19.06, 0.0)]


def rounded_rect(w, d, r, n=6):
    """Closed XY outline (counter-clockwise) of a rounded rectangle."""
    pts = []
    for cx, cy, a0 in ((w / 2 - r, d / 2 - r, 0), (-w / 2 + r, d / 2 - r, 90), (-w / 2 + r, -d / 2 + r, 180),
                       (w / 2 - r, -d / 2 + r, 270)):
        for k in range(n + 1):
            a = math.radians(a0 + 90 * k / n)
            pts.append(Vector((cx + r * math.cos(a), cy + r * math.sin(a), 0.0)))
    return pts


def basket_walls(m):
    """Thick woven walls: outer + inner face + floor, src UV in metres (u along, v up)."""
    outer = rounded_rect(BW, BD, CORNER)
    inner = rounded_rect(BW - 2 * WALL, BD - 2 * WALL, CORNER - WALL)
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new("src")
    zs = (-0.12, 0.0, 0.26, 0.52, BH)

    def wall(path, flip, zlist):
        n = len(path)
        per = [0.0]
        for i in range(1, n + 1):
            per.append(per[-1] + (path[i % n] - path[i - 1]).length)
        rows = [[bm.verts.new(p + Vector((0, 0, z))) for p in path] for z in zlist]
        for j in range(len(zlist) - 1):
            for i in range(n):
                i1 = (i + 1) % n
                quad = [rows[j][i], rows[j][i1], rows[j + 1][i1], rows[j + 1][i]]
                uvs = [(per[i], zlist[j]), (per[i + 1], zlist[j]), (per[i + 1], zlist[j + 1]), (per[i], zlist[j + 1])]
                if flip:
                    quad.reverse()
                    uvs.reverse()
                f = bm.faces.new(quad)
                for loop, uv in zip(f.loops, uvs):
                    loop[uvl].uv = uv
        return rows

    wall(outer, False, zs)
    wall(inner, True, (0.0, 0.26, 0.52, BH))
    # outer bottom
    bot = [bm.verts.new(p + Vector((0, 0, -0.12))) for p in outer]
    f = bm.faces.new(list(reversed(bot)))
    for loop in f.loops:
        loop[uvl].uv = (loop.vert.co.x, loop.vert.co.y)
    obj = geo.finish(bm, "basket_walls", m["wicker"], sharp_angle=50)
    obj["bbd_uv"] = "src"
    obj["bbd_texel"] = 2.6
    return obj


def build_dropship_balloon():
    rng = random.Random(5)
    m = {
        "wicker": mats.wicker(),
        "wicker_lid": mats.wicker("wicker_lid", stake=0.12, weaver=0.05, tint="#b98f55"),
        "gingham": mats.fabric("lining_check", "fabric_pattern_07", density=0.6),
        "rim": mats.fibre("rim_rope", tint="#a77f4c", ply=4, twist=9.0),
        "pine": mats.wood("plank", "coated_pine", coords="box", tint="#d4bea0", rough=0.6),
        "cane": mats.plain("garden_cane", "#c9b07a", rough=0.45, noise_amt=0.2, noise_scale=8.0),
        "leather": mats.leather("leather", density=0.5),
        "brass": mats.metal("brass", "brass", wear=0.6, density=0.3),
        "copper": mats.metal("copper", "copper", density=0.3),
        "steel": mats.metal("steel", "steel", density=0.3),
        "burlap": mats.burlap("burlap", density=0.8),
        "rope": mats.fibre("rope", tint="#b8925a", ply=3, twist=12.0),
    }
    objs = []
    texel_basket = 2.6

    # ---- basket ------------------------------------------------------------
    objs.append(basket_walls(m))
    rim_path = [p + Vector((0, 0, BH)) for p in rounded_rect(BW - WALL, BD - WALL, CORNER - WALL / 2, 8)]
    rim = geo.sweep("rim", rim_path, 0.085, segs=10, mat=m["rim"], closed=True, v_scale=1.0)
    rim["bbd_uv"] = "src"
    objs.append(rim)
    base_path = [p + Vector((0, 0, -0.10)) for p in rounded_rect(BW + 0.02, BD + 0.02, CORNER + 0.01, 8)]
    base = geo.sweep("base_rim", base_path, 0.06, segs=8, mat=m["rim"], closed=True)
    base["bbd_uv"] = "src"
    objs.append(base)
    for k in range(9):  # floor planks
        y = -BD / 2 + WALL + (k + 0.5) * (BD - 2 * WALL) / 9
        objs.append(geo.box(f"plank{k}", (BW - 2 * WALL - 0.05, (BD - 2 * WALL) / 9 - 0.015, 0.03), (0, y, 0.015),
                            m["pine"], bevel=0.008))
    # picnic lids hinged on the long sides, flung open like wings (gingham lining up)
    for sy in (1, -1):
        lo = rounded_rect(BW - 0.1, 1.42, 0.3, 5)
        lo = [(p.x, p.y + 0.71) for p in lo]
        lid = geo.extrude_outline(f"lid{sy}", lo, 0.07, m["wicker_lid"], plane="XY", bevel=0.02, bevel_segs=2)
        lid.data.materials.append(m["gingham"])
        for p in lid.data.polygons:
            if p.normal.z > 0.7:
                p.material_index = 1
        lid.rotation_euler = (math.radians(62), 0.0, 0.0 if sy > 0 else math.pi)
        lid.location = (0.0, sy * (BD / 2 + 0.02), BH + 0.07)
        lid["bbd_texel"] = texel_basket
        objs.append(lid)
        for x in (-1.2, 1.2):  # leather hinge straps
            objs.append(geo.sweep(f"hinge{sy}{x}", [Vector((x, sy * (BD / 2 - 0.10), BH + 0.08)),
                                                    Vector((x, sy * (BD / 2 + 0.06), BH + 0.12)),
                                                    Vector((x, sy * (BD / 2 + 0.10), BH + 0.30))],
                                  0.06, segs=6, mat=m["leather"], flatten=0.18, up=(0, 0, 1)))
    # leather straps + brass buckles on the short ends
    for sx in (1, -1):
        for y in (-0.6, 0.6):
            strap = [Vector((sx * (BW / 2 + 0.012), y, -0.08)), Vector((sx * (BW / 2 + 0.016), y, 0.4)),
                     Vector((sx * (BW / 2 + 0.012), y, BH + 0.05))]
            st = geo.sweep(f"strap{sx}{y}", strap, 0.07, segs=6, mat=m["leather"], flatten=0.15, up=(sx, 0, 0))
            st["bbd_texel"] = texel_basket
            objs.append(st)
            bk = geo.sweep(f"buckle{sx}{y}", [Vector((sx * (BW / 2 + 0.03), y - 0.09, 0.50)),
                                              Vector((sx * (BW / 2 + 0.03), y + 0.09, 0.50)),
                                              Vector((sx * (BW / 2 + 0.03), y + 0.09, 0.36)),
                                              Vector((sx * (BW / 2 + 0.03), y - 0.09, 0.36))],
                           0.014, segs=6, mat=m["brass"], closed=True)
            objs.append(bk)
    # burlap sandbags hanging round the outside
    for k, (x, y) in enumerate(((1.3, 1.55), (-1.3, 1.55), (1.3, -1.55), (-1.3, -1.55), (2.05, 0.0), (-2.05, 0.0))):
        out = Vector((x, y, 0)).normalized()
        c = Vector((x, y, 0.0)) + out * 0.16
        bag = geo.lathe(f"sandbag{k}", [(-0.30, 0.0), (-0.29, 0.12), (-0.22, 0.20), (-0.08, 0.215), (0.06, 0.19),
                                        (0.16, 0.13), (0.21, 0.07), (0.235, 0.045), (0.27, 0.07), (0.30, 0.06),
                                        (0.31, 0.0)], segs=14, mat=m["burlap"], axis="Z", sharp_angle=None)
        geo.displace_noise(bag, 0.03, 5.0, seed=k)
        bag.location = c + Vector((0, 0, 0.12)) + out * 0.08
        objs.append(parts.twine_sleeve(f"bag_tie{k}", bag.location + Vector((0, 0, 0.235)), (0, 0, 1), 0.045, 0.03,
                                       rings=1))
        bag["bbd_texel"] = 1.6
        objs.append(bag)
        hang = geo.sweep(f"bag_rope{k}", [c + out * 0.08 + Vector((0, 0, 0.42)), c - out * 0.02 + Vector((0, 0, 0.64)),
                                          Vector((x, y, BH + 0.02))], 0.012, segs=5, mat=m["rope"])
        hang["bbd_uv"] = "src"
        objs.append(hang)

    # ---- burner on garden canes ---------------------------------------------
    BZ = 3.15
    corners = [Vector((sx * (BW / 2 - 0.35), sy * (BD / 2 - 0.35), BH)) for sx in (1, -1) for sy in (1, -1)]
    for k, c in enumerate(corners):
        top = Vector((c.x * 0.16, c.y * 0.22, BZ))
        cane = geo.sweep(f"cane{k}", [c, c.lerp(top, 0.5), top], 0.035, segs=8, mat=m["cane"])
        objs.append(cane)
        for q in (0.25, 0.55, 0.8):  # bamboo-like nodes
            p = c.lerp(top, q)
            objs.append(parts.band(f"cane_node{k}{q}", p, (top - c), 0.036, 0.03, m["cane"], segs=8))
        objs += parts.knot(f"cane_tie{k}", c + Vector((0, 0, 0.06)), 0.05, seed=k, tails=False)
    ring = geo.sweep("burner_ring", [Vector((0.55 * math.cos(a), 0.55 * math.sin(a), BZ)) for a in
                                     [2 * math.pi * k / 24 for k in range(24)]], 0.04, segs=8, mat=m["brass"],
                     closed=True)
    objs.append(ring)
    coil = geo.sweep("burner_coil", geo.helix((0, 0, BZ - 0.12), (0, 0, 1), 0.30, 0.07, 4, 16), 0.032, segs=8,
                     mat=m["copper"])
    objs.append(coil)
    objs.append(geo.lathe("burner_can", [(BZ - 0.2, 0.0), (BZ - 0.2, 0.14), (BZ + 0.1, 0.14), (BZ + 0.18, 0.10),
                                          (BZ + 0.22, 0.06), (BZ + 0.22, 0.0)], segs=16, mat=m["steel"], axis="Z",
                          sharp_angle=40))
    for k in range(4):
        a = math.pi / 4 + k * math.pi / 2
        objs.append(geo.sweep(f"spoke{k}", [Vector((0.14 * math.cos(a), 0.14 * math.sin(a), BZ)),
                                            Vector((0.55 * math.cos(a), 0.55 * math.sin(a), BZ))], 0.025, segs=6,
                              mat=m["brass"]))

    # ---- envelope -------------------------------------------------------------
    seg_per_gore = 4
    segs = GORES * seg_per_gore

    def puff(i, j, a, t, r):
        g = (a / (2 * math.pi / GORES)) % 1.0
        return r * (0.982 + 0.035 * math.sin(math.pi * g))

    env = geo.lathe("envelope", ENVELOPE, segs=segs, mat=None, cap0=False, cap1=False, axis="Z", radius_fn=puff,
                    sharp_angle=None, phase=0.0)
    env.data.materials.clear()
    band_h = 2.35
    fab = [mats.fabric(f"patch_{ph}", ph, density=0.22, tint=t, gores=GORES, bands=band_h) for ph, t in FABRICS]
    for f_ in fab:
        env.data.materials.append(f_)
    uvl = env.data.uv_layers["src"]
    for poly in env.data.polygons:
        u = sum(uvl.data[li].uv[0] for li in poly.loop_indices) / poly.loop_total
        v = sum(uvl.data[li].uv[1] for li in poly.loop_indices) / poly.loop_total
        gi, bi = int(u * GORES) % GORES, int(v / band_h)
        poly.material_index = (gi * 7 + bi * 3 + (gi // 3) * 5) % len(fab)
    objs.append(env)
    # load tapes on every second seam + crown ring
    for k in range(0, GORES, 2):
        a = 2 * math.pi * k / GORES
        pts = [Vector(((r + 0.035) * math.cos(a), (r + 0.035) * math.sin(a), z)) for z, r in ENVELOPE[2:-1]]
        tape = geo.sweep(f"tape{k}", pts, 0.05, segs=4, mat=m["rope"], flatten=0.4)
        tape["bbd_uv"] = "src"
        objs.append(tape)
    objs.append(geo.sweep("crown_ring", [Vector((0.6 * math.cos(a), 0.6 * math.sin(a), 18.98)) for a in
                                         [2 * math.pi * k / 20 for k in range(20)]], 0.07, segs=6, mat=m["rope"],
                          closed=True))
    objs.append(geo.sweep("throat_ring", [Vector((1.40 * math.cos(a), 1.40 * math.sin(a), 4.85)) for a in
                                          [2 * math.pi * k / 32 for k in range(32)]], 0.06, segs=6, mat=m["rope"],
                          closed=True))
    # carrot greens topknot on the crown (whimsy + reads from far away)
    objs.append(parts.greens("topknot", (0, 0, 18.95), length=2.6, direction=(0, 0, 1), stems=6, seed=21, pairs=3,
                             lobes=3, spread=34, droop=0.35, leaf_scale=1.0, stem_segs=6))
    # rigging: throat ring -> basket rim
    for k in range(8):
        a = 2 * math.pi * (k + 0.5) / 8
        top = Vector((1.40 * math.cos(a), 1.40 * math.sin(a), 4.85))
        d = Vector((math.cos(a), math.sin(a), 0))
        # land on the rounded-rect rim
        t = min((BW / 2 - 0.1) / max(abs(d.x), 1e-6), (BD / 2 - 0.1) / max(abs(d.y), 1e-6))
        bot = Vector((d.x * t, d.y * t, BH + 0.05))
        line = geo.sweep(f"rig{k}", [bot, bot.lerp(top, 0.5) + Vector((0, 0, -0.04)), top], 0.022, segs=5,
                         mat=m["rope"])
        line["bbd_uv"] = "src"
        objs.append(line)
    markers = {
        "Burner": (0.0, 0.0, BZ + 0.25),
        "Exit": (0.0, BD / 2 + 0.05, BH),
    }
    return {"objects": objs, "markers": markers,
            "report": {"notes": "Origin at the basket floor centre; flies toward -Z. Basket interior ~3.76 x 2.76 m "
                                "with 0.78 m walls (critters see over them). `Burner` marks the flame VFX point "
                                "(3.4 m up), `Exit` the front rim where critters jump. One 2048 px atlas "
                                "(basket parts get 2.6x texel density)."}}


ASSETS = {
    "dropship_balloon": dict(build=build_dropship_balloon, out="props", tex=2048, kind="vehicle", target=19.1,
                             use="Battle-royale dropship: patchwork hot-air balloon with a picnic-basket gondola",
                             ao=0.6),
}
