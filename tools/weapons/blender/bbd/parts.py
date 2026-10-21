"""Reusable garden-shed gunsmithing parts (twine wraps, rivets, sights, triggers...).

Everything is built in Blender space (+Y forward, +Z up, metres) and returned
as objects with materials from mats.py; the asset builders compose them.
"""
from __future__ import annotations

import math
import random

from mathutils import Vector

from . import geo, mats


def orient(obj, axis=(0, 1, 0), center=(0, 0, 0)):
    """Rotate an object built along +Y so that +Y points along `axis`, then move it."""
    q = Vector((0, 1, 0)).rotation_difference(Vector(axis).normalized())
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = q
    obj.location = Vector(center)
    return obj


def twine_sleeve(name, center, axis, r, length, thick=0.0024, pitch=0.0034, segs=16, rings=4):
    """A band of coiled twine around a cylinder of radius r (normal-mapped coils)."""
    L = length / 2
    t = thick
    prof = [(-L, r), (-L + t * 0.25, r + t * 0.7), (-L + t, r + t)]
    for k in range(1, rings):
        prof.append((-L + t + (2 * L - 2 * t) * k / rings, r + t))
    prof += [(L - t, r + t), (L - t * 0.25, r + t * 0.7), (L, r)]
    obj = geo.lathe(name, prof, segs=segs, mat=mats.twine_wrap(pitch=pitch), cap0=False, cap1=False,
                    sharp_angle=None)
    obj["bbd_uv"] = "src"
    return orient(obj, axis, center)


def twine_tail(name, start, direction, length=0.03, r=0.0016, seed=0, droop=0.5):
    """A loose twine end hanging from a knot."""
    rng = random.Random(seed)
    d = Vector(direction).normalized()
    pts = []
    for k in range(6):
        q = k / 5
        p = Vector(start) + d * (length * q) + Vector((0, 0, -droop * length * q * q)) \
            + Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), 0)) * (0.002 * q)
        pts.append(p)
    obj = geo.sweep(name, pts, [r] * 5 + [r * 0.6], segs=5, mat=mats.fibre("twine"), caps=True)
    obj["bbd_uv"] = "src"
    return obj


def knot(name, pos, size=0.006, seed=0, tails=True, tail_dir=(0, 0.3, -1)):
    """Small lumpy twine knot (+ two loose ends)."""
    prof = [(-size * 0.6, 0.0), (-size * 0.45, size * 0.55), (0, size * 0.75), (size * 0.45, size * 0.55),
            (size * 0.6, 0.0)]
    k = geo.lathe(name, prof, segs=8, mat=mats.fibre("twine"), axis="X")
    geo.displace_noise(k, size * 0.25, 1.0 / size, seed)
    k.location = Vector(pos)
    out = [k]
    if tails:
        d = Vector(tail_dir)
        out.append(twine_tail(name + "_t1", Vector(pos), d + Vector((0.25, 0, 0)), size * 4.5, size * 0.28, seed))
        out.append(twine_tail(name + "_t2", Vector(pos), d + Vector((-0.25, 0.1, 0)), size * 3.5, size * 0.28,
                              seed + 1))
    return out


def band(name, center, axis, r, width, mat, segs=16, lip=None):
    """Metal ferrule / barrel band: short tube with rounded edges."""
    w = width / 2
    l = lip if lip is not None else min(0.0015, width * 0.2)
    prof = [(-w, r - 0.0004), (-w, r + 0.0006), (-w + l, r + l * 0.9), (w - l, r + l * 0.9),
            (w, r + 0.0006), (w, r - 0.0004)]
    obj = geo.lathe(name, prof, segs=segs, mat=mat, cap0=False, cap1=False, sharp_angle=50)
    return orient(obj, axis, center)


def rivet(name, pos, normal=(1, 0, 0), r=0.0028, mat=None, segs=8):
    prof = [(0.0, r), (r * 0.25, r * 0.92), (r * 0.5, r * 0.6), (r * 0.6, 0.0)]
    obj = geo.lathe(name, prof, segs=segs, mat=mat or mats.metal("brass", "brass"), cap0=True, cap1=False,
                    sharp_angle=60)
    return orient(obj, normal, pos)


def screw(name, pos, normal=(1, 0, 0), r=0.003, mat=None):
    """Slotted screw head (slot made of two flattened half-domes)."""
    prof = [(0.0, r), (r * 0.2, r * 0.95), (r * 0.42, r * 0.55), (r * 0.48, 0.0)]
    obj = geo.lathe(name, prof, segs=10, mat=mat or mats.metal("steel", "steel"), sharp_angle=60)
    return orient(obj, normal, pos)


def bead(name, pos, r=0.003, mat=None):
    prof = [(-r, 0.0), (-r * 0.7, r * 0.72), (0, r), (r * 0.7, r * 0.72), (r, 0.0)]
    obj = geo.lathe(name, prof, segs=10, mat=mat or mats.metal("brass", "brass"), axis="Z")
    obj.location = Vector(pos)
    return obj


def trigger(name, pos, scale=1.0, mat=None):
    """Curved trigger blade (side view outline, extruded thin)."""
    s = scale
    o = [(0.000, 0.000), (0.004, -0.004), (0.006, -0.012), (0.004, -0.020), (0.000, -0.024),
         (-0.002, -0.022), (0.001, -0.016), (0.001, -0.008), (-0.003, -0.002), (-0.003, 0.004), (0.0, 0.004)]
    o = [(a * s, b * s) for a, b in o]
    obj = geo.extrude_outline(name, geo.chaikin(o, 1), 0.006 * s, mat or mats.metal("blued", "blued"),
                              bevel=0.0012 * s, bevel_segs=1)
    obj.location = Vector(pos)
    return obj


def trigger_guard(name, front, back, depth, width=0.007, thick=0.0028, mat=None):
    """Bent-strap trigger guard from `front` (y,z) to `back` (y,z) dipping `depth` below."""
    fy, fz = front
    by, bz = back
    pts = []
    n = 12
    for k in range(n):
        q = k / (n - 1)
        y = fy + (by - fy) * q
        z = fz + (bz - fz) * q - depth * math.sin(math.pi * q) ** 0.8
        pts.append((0.0, y, z))
    obj = geo.sweep(name, pts, width / 2, segs=6, mat=mat or mats.metal("brass", "brass"), caps=True,
                    flatten=thick / width, up=(1, 0, 0))
    return obj


def notch_sight(name, pos, w=0.016, h=0.010, notch=0.004, depth=0.006, mat=None):
    """Rear sight blade (front view outline) with a U notch, extruded along Y."""
    hw = w / 2
    o = [(-hw, 0.0), (hw, 0.0), (hw, h), (notch * 0.6, h), (notch * 0.5, h - notch * 0.6),
         (0.0, h - notch), (-notch * 0.5, h - notch * 0.6), (-notch * 0.6, h), (-hw, h)]
    obj = geo.extrude_outline(name, o, depth, mat or mats.metal("blued", "blued"), plane="XZ",
                              bevel=0.0008, bevel_segs=1)
    obj.location = Vector(pos)
    return obj


def post_sight(name, pos, h=0.012, w=0.003, depth=0.004, mat=None):
    o = [(-w * 1.6, 0.0), (w * 1.6, 0.0), (w * 0.5, h * 0.35), (w * 0.5, h), (-w * 0.5, h), (-w * 0.5, h * 0.35)]
    obj = geo.extrude_outline(name, o, depth, mat or mats.metal("brass", "brass"), plane="XZ",
                              bevel=0.0006, bevel_segs=1)
    obj.location = Vector(pos)
    return obj


def greens(name, pos, length=0.06, direction=(0, 0, 1), stems=3, seed=0, pairs=3, lobes=2, spread=30.0,
           droop=0.2, leaf_scale=1.0, stem_segs=4):
    """Carrot-top sprig (leafy sight / flag)."""
    obj = geo.carrot_greens(name, length=length, stems=stems, pairs=pairs, lobes=lobes, seed=seed,
                            mat=mats.leaf(), stem_mat=mats.leaf("carrot_stem", color="#6a9a3a", vein="#8fbf5a"),
                            direction=direction, spread=spread, droop=droop, leaf_scale=leaf_scale,
                            stem_segs=stem_segs, stem_r=max(0.0018, length * 0.012))
    obj.location = Vector(pos)
    return obj


def carrot_part(name, length, radius, pos=(0, 0, 0), axis=(0, 1, 0), seed=0, segs=14, rings=10,
                bend=0.0, cut=0.0, bumps=0.05, v_range=(0.1, 0.98), power=1.15, tip_round=0.06):
    """A carrot (tip toward +axis). `cut` truncates the tip fraction (barrel exits there)."""
    obj = geo.carrot(name, length, radius, segs=segs, rings=rings, mat=mats.carrot_skin(), seed=seed,
                     bend=bend, bumps=bumps, power=power, tip_round=tip_round)
    obj["bbd_uv"] = "src"
    if cut > 0:
        _truncate_tip(obj, length * cut)
    # geo.carrot points its tip to -Y; flip so the tip points along +axis
    flip = Vector(axis).normalized()
    return orient(obj, -flip, pos)


def _truncate_tip(obj, t_cut):
    """Delete geometry below t_cut (tip end) and close the hole flat."""
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
    res = bmesh.ops.bisect_plane(bm, geom=geom, dist=1e-6, plane_co=(0, t_cut, 0), plane_no=(0, 1, 0),
                                 clear_inner=True)
    cut_edges = [e for e in res["geom_cut"] if isinstance(e, bmesh.types.BMEdge)]
    if cut_edges:
        bmesh.ops.edgeloop_fill(bm, edges=cut_edges)
    bm.to_mesh(obj.data)
    bm.free()
