"""Glider variants for the battle-royale drop: big plant parasols held overhead.

Each is 1.7-2.3 m across, with its origin at the hand grip (Hand_L / Hand_R IK
markers 4.5 cm above / below it) and the canopy overhead. Thin canopies (leaves,
petals, fluff) use two-sided alpha-scissor materials made from real scans:
  * oak / maple leaves  - top-down planar re-skins of a red oak leaf and a red maple leaf scan
  * tulip               - cylindrical petal strip unwrapped from a red tulip scan
  * daisy               - a daisy head cut from ambientCG FlowerSet001 (CC0)
  * dandelion plume     - the code-generated pappus bristle, slightly emissive
  * parasol mushroom    - baked: cap re-skinned from a shaggy parasol scan, gills and stipe procedural
Stems, handles and anything solid are baked into the usual 1024 px atlas.

Blender space: +Z up, front -Y (glTF +Z); everything hangs off the grip at the origin.
"""
from __future__ import annotations

import math
import random

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

from bbd import geo, mats, parts, plants

HANDS = {"Hand_L": (0.0, 0.0, 0.045), "Hand_R": (0.0, 0.0, -0.045)}


def _alpha(png):
    img = bpy.data.images.load(png, check_existing=True)
    w, h = img.size
    a = np.empty(w * h * 4, np.float32)
    img.pixels.foreach_get(a)
    return a.reshape(h, w, 4)[..., 3]


def grip(name="grip_wrap", r=0.022, length=0.11):
    return parts.twine_sleeve(name, (0, 0, 0.0), (0, 0, 1), r, length, rings=3)


def stalk(name, pts, r0, r1, mat, segs=10):
    n = len(pts)
    return geo.sweep(name, [Vector(p) for p in pts], [r0 + (r1 - r0) * k / (n - 1) for k in range(n)], segs=segs,
                     mat=mat)


def card_grid(name, mat, uv_rect, res, alpha, to3d, keep_margin=1):
    """Grid over a texture rectangle, dropping cells whose texels are all transparent.

    to3d(u, v) -> Vector places a texture coordinate on the canopy surface.
    """
    u0, v0, u1, v1 = uv_rect
    nu, nv = res
    h, w = alpha.shape
    keep = np.zeros((nv, nu), bool)
    for j in range(nv):
        for i in range(nu):
            uu = np.linspace(u0 + (u1 - u0) * i / nu, u0 + (u1 - u0) * (i + 1) / nu, 5)
            vv = np.linspace(v0 + (v1 - v0) * j / nv, v0 + (v1 - v0) * (j + 1) / nv, 5)
            xs = np.clip((uu * w).astype(int), 0, w - 1)
            ys = np.clip((vv * h).astype(int), 0, h - 1)
            keep[j, i] = alpha[np.ix_(ys, xs)].max() > 0.2
    if keep_margin:
        k2 = keep.copy()
        k2[1:] |= keep[:-1]
        k2[:-1] |= keep[1:]
        k2[:, 1:] |= keep[:, :-1]
        k2[:, :-1] |= keep[:, 1:]
        keep = k2
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new("src")
    verts = {}

    def vert(i, j):
        if (i, j) not in verts:
            u = u0 + (u1 - u0) * i / nu
            v = v0 + (v1 - v0) * j / nv
            verts[(i, j)] = (bm.verts.new(to3d(u, v)), (u, v))
        return verts[(i, j)]

    for j in range(nv):
        for i in range(nu):
            if not keep[j, i]:
                continue
            q = [vert(i, j), vert(i + 1, j), vert(i + 1, j + 1), vert(i, j + 1)]
            f = bm.faces.new([x[0] for x in q])
            for loop, (_, uv) in zip(f.loops, q):
                loop[uvl].uv = uv
    bm.normal_update()
    if sum(f.normal.z for f in bm.faces) < 0:      # face up (two-sided anyway, but keeps normals sane)
        bmesh.ops.reverse_faces(bm, faces=bm.faces[:])
    obj = geo.finish(bm, name, mat, sharp_angle=None)
    obj["bbd_bake"] = False
    return obj


# --------------------------------------------------------------------------- leaves

def leaf_glider(kind):
    """Giant autumn leaf held by its stalk: oak (long, curled sides) or maple (round dome)."""
    if kind == "oak":
        png, nrm, src = mats.derived("oak_leaf_albedo.png"), mats.derived("oak_leaf_normal.png"), "oak_leaf"
        S, centre, zc = 2.35, (0.50, 0.53), 0.98
        stem_col, rot = "#8a4626", 0.0
    else:
        png, nrm, src = mats.derived("maple_leaf_albedo.png"), mats.derived("maple_leaf_normal.png"), "maple_leaf_scan"
        S, centre, zc = 2.45, None, 0.98
        stem_col, rot = "#7a2c1c", None
    alpha = _alpha(png)
    h, w = alpha.shape
    ys, xs = np.nonzero(alpha > 0.5)
    if centre is None:
        centre = (xs.mean() / w, ys.mean() / h)
    # stalk end: for oak it is the bottom of the image; for maple find the thin protrusion
    if kind == "oak":
        sel = ys < np.percentile(ys, 1.5)
        stem_uv = (xs[sel].mean() / w, ys[sel].mean() / h)
    else:
        d = np.hypot(xs / w - centre[0], ys / h - centre[1])
        band = (np.abs(ys / h - centre[1]) < 0.12)
        k = np.argmax(np.where(band, xs, -1))
        stem_uv = (xs[k] / w, ys[k] / h)
    sdir = Vector((stem_uv[0] - centre[0], stem_uv[1] - centre[1])).normalized()
    ang = math.atan2(sdir.x, sdir.y)           # rotate so the stalk points backwards (+Y)
    ca, sa = math.cos(ang), math.sin(ang)

    def plane(u, v):
        x, y = (u - centre[0]) * S, (v - centre[1]) * S
        return Vector((x * ca - y * sa, x * sa + y * ca))

    def to3d(u, v):
        p = plane(u, v)
        x, y = p.x, p.y
        r = math.hypot(x, y)
        if kind == "oak":   # cupped across, tip curling down at the front, slight twist
            z = zc - 0.42 * x * x - 0.08 * y * y - 0.22 * max(0.0, -y - 0.5) ** 2 + 0.05 * x * y
        else:               # maple: umbrella dome, lobes waving
            th = math.atan2(y, x)
            z = zc - 0.30 * r * r + 0.045 * math.sin(5 * th + 0.7) * r * r
        return Vector((x, y, z))

    mat = mats.alpha_card(f"{kind}_leaf_card", png, rough=0.62, sheen=0.0, cutoff=0.5, normal_png=nrm,
                          normal_strength=0.8, sources=(src,))
    can = card_grid(f"{kind}_canopy", mat, (0.0, 0.0, 1.0, 1.0), (30, 30), alpha, to3d)
    objs = [can]
    base = to3d(*stem_uv)
    stem_mat = mats.plain(f"{kind}_stalk", stem_col, rough=0.55, noise_amt=0.15, noise_scale=30.0)
    pts = [base, base + Vector((0, -0.03, -0.18)), Vector((0, base.y * 0.65, base.z * 0.45)),
           Vector((0, base.y * 0.2, 0.08)), Vector((0, 0, -0.02)), Vector((0, 0, -0.15))]
    objs.append(stalk(f"{kind}_stalk", pts, 0.012, 0.021, stem_mat))
    objs.append(grip())
    return {"objects": objs, "markers": dict(HANDS),
            "report": {"notes": f"Origin at the hand grip on the leaf stalk; the {kind} leaf canopy is a two-sided "
                                "alpha-scissor card (scanned leaf texture) ~1 m overhead, stalk curving down to "
                                "the hands."}}


def build_glider_oak_leaf():
    return leaf_glider("oak")


def build_glider_maple_leaf():
    return leaf_glider("maple")


# --------------------------------------------------------------------------- daisy

def build_glider_daisy():
    png, nrm = mats.derived("daisy_head_albedo.png"), mats.derived("daisy_head_normal.png")
    mat = mats.alpha_card("daisy_card", png, rough=0.6, sheen=0.4, cutoff=0.5, normal_png=nrm, normal_strength=0.7,
                          sources=("FlowerSet001",))
    R_TEX, ZC, N_PETAL = 1.17, 0.95, 15
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new("src")
    rings, segs = 13, 48
    grid = []
    for i in range(rings + 1):
        r = R_TEX * (i / rings) ** 0.9
        row = []
        for j in range(segs if i else 1):
            th = 2 * math.pi * j / segs
            x, y = r * math.cos(th), r * math.sin(th)
            z = ZC - 0.17 * (r / 1.1) ** 2.2 + 0.035 * math.sin(N_PETAL * th) * (r / 1.1) ** 2
            if r < 0.34:
                z += 0.11 * (1 - (r / 0.34) ** 2) ** 2   # the domed yellow disc florets
            row.append((bm.verts.new((x, y, z)), (0.5 + x / (2 * R_TEX), 0.5 + y / (2 * R_TEX))))
        grid.append(row)
    for i in range(rings):
        A, B = grid[i], grid[i + 1]
        for j in range(segs):
            j1 = (j + 1) % segs
            q = [A[0], B[j], B[j1]] if len(A) == 1 else [A[j], B[j], B[j1], A[j1]]
            f = bm.faces.new([x[0] for x in q])
            for loop, (_, uv) in zip(f.loops, q):
                loop[uvl].uv = uv
    bm.normal_update()
    if sum(f.normal.z for f in bm.faces) < 0:
        bmesh.ops.reverse_faces(bm, faces=bm.faces[:])
    can = geo.finish(bm, "daisy_canopy", mat, sharp_angle=None)
    can["bbd_bake"] = False
    green = mats.leaf("daisy_green", color="#4c7d2e", vein="#6d9b45")
    bracts = geo.lathe("bracts", [(ZC - 0.20, 0.03), (ZC - 0.12, 0.10), (ZC - 0.05, 0.25), (ZC - 0.035, 0.30)],
                       segs=24, mat=green, axis="Z", cap0=False, cap1=False, sharp_angle=None,
                       radius_fn=lambda i, j, a, t, r: r * (0.85 + 0.15 * abs(math.cos(10 * a))))
    stem = stalk("stem", [(0, 0, ZC - 0.18), (0.01, 0.0, 0.6), (0.0, 0.01, 0.3), (0, 0, -0.15)], 0.024, 0.024,
                 mats.plain("daisy_stem", "#5b8a36", rough=0.5, noise_amt=0.12))
    leaf = geo.extrude_outline("stem_leaf", geo.chaikin([(0, 0), (0.08, 0.035), (0.22, 0.05), (0.3, 0.02), (0.3, -0.02),
                                                          (0.2, -0.045), (0.08, -0.03)], 2), 0.008, green,
                               plane="XZ", bevel=0.003, bevel_segs=1)
    leaf.matrix_world = Matrix.Translation((0.02, 0, 0.42)) @ Matrix.Rotation(math.radians(-35), 4, "Y")
    return {"objects": [can, bracts, stem, leaf, grip()], "markers": dict(HANDS),
            "report": {"notes": "Origin at the hand grip; daisy-head parasol (ambientCG CC0 daisy, two-sided "
                                "alpha-scissor) 2.2 m across, ~0.95 m overhead."}}


# --------------------------------------------------------------------------- tulip

def build_glider_tulip():
    png, nrm = mats.derived("tulip_strip_albedo.png"), mats.derived("tulip_strip_normal.png")
    mat = mats.alpha_card("tulip_petal", png, rough=0.45, sheen=0.0, cutoff=0.0, normal_png=nrm, normal_strength=0.6,
                          sources=("tulip_scan",))
    ZT, DROP = 1.36, 0.94
    V_BASE, V_TIP = 0.80, 0.06
    petals = []
    for k in range(6):
        outer = k % 2 == 0
        a0 = math.radians(60 * k)
        phimax = math.radians(37 if outer else 33)
        scale = 1.0 if outer else 0.955
        u_lo = (k // 2) / 3 + (0 if outer else 1 / 6)
        bm = bmesh.new()
        uvl = bm.loops.layers.uv.new("src")
        ns, nt = 10, 7
        grid = []
        for i in range(ns + 1):
            sv = i / ns
            R = (0.08 + 0.86 * math.sin(min(1.0, sv * 1.12) * math.pi / 2) + 0.07 * sv ** 5) * scale
            z = ZT - DROP * sv ** 1.25 - (0 if outer else 0.012)
            phi = phimax * (0.42 + 0.58 * math.sin(math.pi * min(sv, 0.92)) ** 0.5) * math.sqrt(max(0.02, 1 - sv ** 7))
            row = []
            for j in range(nt + 1):
                tt = -1 + 2 * j / nt
                a = a0 + tt * phi
                rr = R * (1 - 0.06 * tt * tt)
                row.append((bm.verts.new((rr * math.cos(a), rr * math.sin(a), z + 0.02 * tt * tt * sv)),
                            (u_lo + (tt + 1) / 2 / 3, V_BASE + (V_TIP - V_BASE) * sv)))
            grid.append(row)
        for i in range(ns):
            for j in range(nt):
                q = [grid[i][j], grid[i][j + 1], grid[i + 1][j + 1], grid[i + 1][j]]
                f = bm.faces.new([x[0] for x in q])
                for loop, (_, uv) in zip(f.loops, q):
                    loop[uvl].uv = uv
        p = geo.finish(bm, f"petal{k}", mat, sharp_angle=None)
        p["bbd_bake"] = False
        petals.append(p)
    green = mats.plain("tulip_green", "#4f8a32", rough=0.45, noise_amt=0.1)
    pale = mats.plain("pistil", "#d6dc94", rough=0.5, noise_amt=0.1)
    dark = mats.plain("anther", "#2c1d2e", rough=0.6, noise_amt=0.15)
    objs = list(petals)
    objs.append(geo.lathe("receptacle", [(ZT - 0.06, 0.0), (ZT - 0.04, 0.10), (ZT + 0.02, 0.10), (ZT + 0.08, 0.05),
                                         (ZT + 0.10, 0.0)], segs=16, mat=green, axis="Z", sharp_angle=None))
    # curled stem with a leaf on top (silhouette), pistil hanging down as the handle
    stem_pts = [(0, 0, ZT + 0.08), (0, 0.04, ZT + 0.26), (0, 0.18, ZT + 0.40), (0, 0.36, ZT + 0.40), (0, 0.46, ZT + 0.28),
                (0, 0.44, ZT + 0.18)]
    objs.append(stalk("stem", stem_pts, 0.03, 0.022, green))
    leaf = geo.extrude_outline("tulip_leaf", geo.chaikin([(0, 0), (0.12, 0.07), (0.38, 0.09), (0.62, 0.04), (0.7, 0.0),
                                                           (0.6, -0.03), (0.35, -0.06), (0.12, -0.05)], 2), 0.012,
                               green, plane="XZ", bevel=0.004, bevel_segs=1)
    leaf.matrix_world = (Matrix.Translation((0.02, 0.10, ZT + 0.30)) @ Matrix.Rotation(math.radians(-90), 4, "Z")
                         @ Matrix.Rotation(math.radians(28), 4, "Y"))
    objs.append(leaf)
    objs.append(stalk("pistil", [(0, 0, ZT - 0.04), (0, 0, ZT - 0.5), (0, 0, 0.3), (0, 0, -0.15)], 0.03, 0.026, pale))
    for k in range(3):
        a = 2 * math.pi * k / 3
        b = geo.lathe(f"stigma{k}", [(-0.035, 0.0), (-0.02, 0.028), (0.02, 0.028), (0.035, 0.0)], segs=10, mat=pale,
                      axis="Z", sharp_angle=None)
        b.location = (0.03 * math.cos(a), 0.03 * math.sin(a), ZT - 0.13)
        objs.append(b)
    for k in range(6):
        a = 2 * math.pi * (k + 0.5) / 6
        d = Vector((math.cos(a), math.sin(a), 0))
        top, bot = Vector((0, 0, ZT - 0.05)) + d * 0.05, Vector((0, 0, ZT - 0.42)) + d * 0.13
        objs.append(stalk(f"filament{k}", [top, top.lerp(bot, 0.5), bot], 0.006, 0.005, pale, segs=5))
        an = geo.lathe(f"anther{k}", [(-0.05, 0.0), (-0.035, 0.014), (0.035, 0.014), (0.05, 0.0)], segs=8, mat=dark,
                       axis="Z", sharp_angle=None)
        an.location = bot + Vector((0, 0, -0.04))
        objs.append(an)
    objs.append(grip(r=0.027))
    return {"objects": objs, "markers": dict(HANDS),
            "report": {"notes": "Origin at the hand grip on the pistil; upside-down tulip bell (petals from the "
                                "tulip scan, two-sided) ~2 m across, mouth 0.4 m above the grip, top 1.8 m."}}


# --------------------------------------------------------------------------- dandelion plume

def build_glider_dandelion_plume():
    ZC = 0.86
    objs = []
    rng = random.Random(9)
    n_all, dirs = 92, []
    for k in range(n_all):          # Fibonacci sphere, keep the upper part + a skirt below the equator
        z = 1 - 2 * (k + 0.5) / n_all
        r = math.sqrt(1 - z * z)
        th = k * math.pi * (3 - math.sqrt(5))
        if z > -0.40:
            dirs.append(Vector((r * math.cos(th), r * math.sin(th), z)))
    beak_mat = mats.plain("beak", "#e6e7d2", rough=0.5, noise_amt=0.05)
    for k, d in enumerate(dirs):
        start = Vector((0, 0, ZC)) + d * 0.07
        L = 0.40 * rng.uniform(0.92, 1.08)
        end = start + d * L
        objs.append(geo.sweep(f"beak{k}", [start, end], [0.0055, 0.0035], segs=3, mat=beak_mat, caps=False))
        objs.append(plants.pappus(f"tuft{k}", end, 0.40 * rng.uniform(0.9, 1.1), n=14, rise=0.55, droop=0.02,
                                  width=0.24, seed=k, axis=d, segs=1, emission=0.4, mat_name="pappus_glow"))
    objs.append(geo.lathe("receptacle", [(ZC - 0.07, 0.0), (ZC - 0.065, 0.05), (ZC, 0.075), (ZC + 0.05, 0.05),
                                         (ZC + 0.075, 0.0)], segs=16, mat=mats.plain("receptacle", "#8a7a4a", rough=0.7,
                                                                                   noise_amt=0.3, noise_scale=200.0),
                          axis="Z", sharp_angle=None))
    bracts = geo.lathe("bracts", [(ZC - 0.06, 0.04), (ZC - 0.12, 0.07), (ZC - 0.22, 0.10)], segs=20,
                       mat=mats.leaf("bract", color="#4d7d2c", vein="#6d9a45"), axis="Z", cap0=False, cap1=False,
                       sharp_angle=None, radius_fn=lambda i, j, a, t, r: r * (0.7 + 0.3 * abs(math.cos(8 * a))))
    objs.append(bracts)
    objs.append(stalk("stalk", [(0, 0, ZC - 0.06), (0.005, 0, 0.5), (0, 0.004, 0.2), (0, 0, -0.15)], 0.02, 0.024,
                      mats.plain("dandelion_stalk", "#a9b46a", rough=0.45, noise_amt=0.15)))
    objs.append(grip())
    return {"objects": objs, "markers": dict(HANDS),
            "report": {"notes": "Origin at the hand grip on the stalk; a giant dandelion clock of glowing "
                                "alpha-scissor pappus tufts (~1.9 m across), centre 0.86 m overhead."}}


# --------------------------------------------------------------------------- parasol mushroom

def build_glider_mushroom():
    ZC = 0.86
    cap_png, cap_n = mats.derived("parasol_cap_albedo.png"), mats.derived("parasol_cap_normal.png")
    capm = mats.planar_image("parasol_cap", cap_png, sources=("parasol_scan",), rough=0.75, normal_png=cap_n,
                             normal_strength=0.9)
    top = [(ZC - 0.065, 1.0), (ZC + 0.015, 0.96), (ZC + 0.12, 0.82), (ZC + 0.22, 0.62), (ZC + 0.29, 0.42),
           (ZC + 0.34, 0.22), (ZC + 0.375, 0.10), (ZC + 0.405, 0.04), (ZC + 0.41, 0.0)]
    cap = geo.lathe("cap", top, segs=48, mat=capm, cap0=False, cap1=False, axis="Z", sharp_angle=None,
                    radius_fn=lambda i, j, a, t, r: r * (1 + 0.012 * math.sin(7 * a) * (r > 0.9)))
    uvl = cap.data.uv_layers["src"]
    for li, loop in enumerate(cap.data.loops):     # planar (top-down) UVs onto the re-skinned cap photo
        co = cap.data.vertices[loop.vertex_index].co
        uvl.data[li].uv = (0.4995 + 0.47 * co.x, 0.4995 + 0.47 * co.y)
    under = geo.lathe("gills", [(ZC + 0.10, 0.055), (ZC + 0.07, 0.30), (ZC + 0.0, 0.70), (ZC - 0.075, 0.985),
                                (ZC - 0.065, 1.0)], segs=48, mat=mats.gills(), cap0=False, cap1=False, axis="Z",
                      sharp_angle=None)
    under["bbd_uv"] = "src"
    st = mats.stipe()
    stipe = geo.lathe("stipe", [(-0.16, 0.0), (-0.16, 0.06), (-0.12, 0.10), (-0.06, 0.085), (0.05, 0.055),
                                (0.5, 0.048), (ZC + 0.11, 0.045)], segs=16, mat=st, cap0=True, cap1=False, axis="Z",
                      sharp_angle=None)
    ring = geo.lathe("annulus", [(ZC - 0.30, 0.05), (ZC - 0.33, 0.10), (ZC - 0.30, 0.135), (ZC - 0.26, 0.13),
                                 (ZC - 0.24, 0.09), (ZC - 0.25, 0.05)], segs=24,
                     mat=mats.plain("annulus", "#ece0c8", rough=0.75, noise_amt=0.2, noise_scale=90.0),
                     cap0=False, cap1=False, axis="Z", sharp_angle=None)
    return {"objects": [cap, under, stipe, ring, grip(r=0.05, length=0.12)], "markers": dict(HANDS),
            "report": {"notes": "Origin at the hand grip on the stipe; parasol-mushroom cap (re-skinned from a "
                                "shaggy parasol scan) 2 m across, ~0.9-1.3 m overhead."}}


ASSETS = {
    "glider_dandelion_plume": dict(build=build_glider_dandelion_plume, out="props", tex=512, kind="glider", capsule=1.1,
                                   use="Drop glider: giant glowing dandelion clock"),
    "glider_oak_leaf": dict(build=build_glider_oak_leaf, out="props", tex=512, kind="glider", capsule=1.1,
                            use="Drop glider: giant curled autumn oak leaf held by its stalk"),
    "glider_maple_leaf": dict(build=build_glider_maple_leaf, out="props", tex=512, kind="glider", capsule=1.1,
                              use="Drop glider: giant red maple leaf"),
    "glider_tulip": dict(build=build_glider_tulip, out="props", tex=512, kind="glider", capsule=1.1,
                         use="Drop glider: upside-down tulip bell, held by the pistil"),
    "glider_daisy": dict(build=build_glider_daisy, out="props", tex=512, kind="glider", capsule=1.1,
                         use="Drop glider: daisy-head parasol"),
    "glider_mushroom": dict(build=build_glider_mushroom, out="props", tex=1024, kind="glider", capsule=1.1,
                            use="Drop glider: parasol-mushroom cap"),
}
