"""Plant bits shared by the props: dandelion pappus parachutes, achene seeds,
four-leaf clovers and dandelion flowers."""
from __future__ import annotations

import math
import random

import bmesh
from mathutils import Matrix, Vector

from . import geo, mats, textures


def pappus(name, center, radius, n=110, rise=0.30, droop=0.08, width=0.11, seed=1):
    """Fluffy crown of alpha-tested bristle cards radiating from `center` (dandelion pappus).

    Bristles fan out at varied elevations (a shallow, upward-open crown like a
    real dandelion seed) and each card is rolled randomly about its own axis, so
    the tuft reads as fluff from below, the side and above.
    Bristle cards: v = 0 at the centre, 1 at the tip (see textures.pappus_bristle).
    Not baked: the material is exported directly as an alpha-mask texture.
    """
    rng = random.Random(seed)
    tex = textures.pappus_bristle()
    mat = mats.alpha_card("pappus", tex, "#fbf9f2", rough=0.8, sheen=0.7)
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new("src")
    c = Vector(center)
    segs = 3
    for k in range(n):
        az = 2 * math.pi * (k + rng.uniform(-0.45, 0.45)) / n
        rad = radius * rng.uniform(0.82, 1.05)
        el = rise * rng.uniform(0.3, 1.6)
        out = Vector((math.cos(az), math.sin(az), 0.0))
        tang = Vector((-math.sin(az), math.cos(az), 0.0))
        pts = []
        for i in range(segs + 1):
            q = i / segs
            h = el * rad * math.sin(q * math.pi * 0.5) - droop * rad * q ** 3
            pts.append(c + out * (rad * q) + Vector((0, 0, h)))
        axis = (pts[-1] - pts[0]).normalized()
        roll = rng.uniform(0.0, math.pi)
        side_dir = (Matrix.Rotation(roll, 3, axis) @ tang).normalized()
        for side in (1, -1):
            verts = []
            for i, p in enumerate(pts):
                q = i / segs
                w = rad * width * (0.12 + 0.88 * q ** 0.7) * 0.5
                off = side_dir.cross(axis) * (0.0005 * side)
                verts.append((bm.verts.new(p - side_dir * w + off), bm.verts.new(p + side_dir * w + off), q))
            for i in range(segs):
                a0, a1, qa = verts[i]
                b0, b1, qb = verts[i + 1]
                quad = [a0, b0, b1, a1] if side > 0 else [a1, b1, b0, a0]
                f = bm.faces.new(quad)
                uvs = {a0: (0.0, qa), b0: (0.0, qb), b1: (1.0, qb), a1: (1.0, qa)}
                for loop in f.loops:
                    loop[uvl].uv = uvs[loop.vert]
    obj = geo.finish(bm, name, mat, sharp_angle=None)
    obj["bbd_bake"] = False
    return obj


def achene(name, base, length, radius, seed=0, mat=None):
    """Dandelion seed body: ribbed spindle with a tiny barbed shoulder; tip up at base+length."""
    ribs = 10

    def rf(i, j, a, t, r):
        return r * (1.0 + 0.10 * abs(math.sin(ribs * a * 0.5)))
    prof = [(0.0, 0.0), (0.08, 0.45), (0.25, 0.85), (0.5, 1.0), (0.72, 0.8), (0.88, 0.45), (0.97, 0.25),
            (1.0, 0.0)]
    prof = [(t * length, r * radius) for t, r in prof]
    obj = geo.lathe(name, prof, segs=12, mat=mat or mats.plain("achene", "#6b5a2e", rough=0.6, noise_amt=0.15),
                    axis="Z", radius_fn=rf, sharp_angle=None)
    geo.displace_noise(obj, radius * 0.05, 40.0 / max(radius, 1e-3) * 0.01, seed)
    obj.location = Vector(base)
    return obj


def beak(name, base, top, radius, mat=None):
    """The long thin stalk between seed and pappus."""
    pts = [Vector(base).lerp(Vector(top), q) for q in (0.0, 0.33, 0.66, 1.0)]
    return geo.sweep(name, pts, [radius, radius * 0.9, radius * 0.8, radius * 0.7], segs=6,
                     mat=mat or mats.plain("beak", "#d9dcc0", rough=0.5, noise_amt=0.05))


def heart_outline(n=26, width=0.78):
    """Obcordate leaflet: point at the base (0,0), notched tip at x = 1."""
    pts = []
    for k in range(n):
        t = 2 * math.pi * k / n
        hx = 16 * math.sin(t) ** 3
        hy = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)
        pts.append(((hy + 17.0) / 22.0, hx / 22.0 * width))
    return pts


def clover(name, center, size, normal=(0, 0, 1), up_hint=(0, 1, 0), leaves=4, stem_len=0.0, seed=0,
           mat=None, stem_mat=None, cup=0.18):
    """A clover (four leaflets by default) lying in the plane with the given normal."""
    rng = random.Random(seed)
    mat = mat or mats.clover_leaf()
    nrm = Vector(normal).normalized()
    ref = Vector(up_hint)
    e1 = (ref - nrm * ref.dot(nrm)).normalized()
    e2 = nrm.cross(e1)
    c = Vector(center)
    outline = heart_outline()
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new("src")
    for k in range(leaves):
        a = 2 * math.pi * k / leaves + rng.uniform(-0.08, 0.08) + math.pi / 4
        d = e1 * math.cos(a) + e2 * math.sin(a)
        w = nrm.cross(d)
        s = size * rng.uniform(0.92, 1.05)
        for side in (1, -1):
            cen_uv = (0.45, 0.5)
            cen = c + d * (0.45 * s) + nrm * (cup * s * 0.25 + 0.0005 * side)
            vc = bm.verts.new(cen)
            ring = []
            for (x, y) in outline:
                lift = cup * s * (x * x * 0.6 + abs(y) * 0.4) * 0.5
                ring.append((bm.verts.new(c + d * (x * s) + w * (y * s) + nrm * (lift + 0.0005 * side)), (x, 0.5 + y)))
            for i in range(len(ring)):
                v0, uv0 = ring[i]
                v1, uv1 = ring[(i + 1) % len(ring)]
                tri = [vc, v0, v1] if side > 0 else [vc, v1, v0]
                f = bm.faces.new(tri)
                uvs = {vc: cen_uv, v0: uv0, v1: uv1}
                for loop in f.loops:
                    loop[uvl].uv = uvs[loop.vert]
    obj = geo.finish(bm, name, mat, sharp_angle=None)
    parts = [obj]
    if stem_len > 0:
        pts = [c - nrm * 0.002, c - nrm * (stem_len * 0.3) + e1 * stem_len * 0.1, c - nrm * stem_len + e1 * stem_len * 0.15]
        parts.append(geo.sweep(name + "_stem", pts, size * 0.035, segs=5,
                               mat=stem_mat or mats.leaf("clover_stem", color="#5e8f3a", vein="#7fb05a")))
    from .util import join
    return join(parts, name)


def dandelion_flower(name, center, radius, normal=(0, 0, 1), seed=0):
    """Yellow dandelion head: two layers of fringed ray florets over green bracts."""
    nrm = Vector(normal).normalized()
    yellow = mats.plain("dandelion_yellow", "#f3c316", rough=0.55, noise_amt=0.2, noise_scale=300.0, sheen=0.5)
    green = mats.leaf("bract", color="#4d7d2c", vein="#6d9a45")
    parts = []
    for layer, (rr, h, n) in enumerate(((1.0, 0.25, 22), (0.72, 0.42, 16))):
        def rf(i, j, a, t, r, n=n):
            return r * (0.78 + 0.22 * abs(math.cos(n * a * 0.5))) if i >= 2 else r
        prof = [(0.0, 0.0), (radius * h * 0.6, radius * rr * 0.35), (radius * h, radius * rr * 0.9),
                (radius * h * 0.85, radius * rr)]
        parts.append(geo.lathe(f"{name}_rays{layer}", prof, segs=n * 2, mat=yellow, axis="Z", radius_fn=rf,
                               cap1=False, sharp_angle=None))
    bracts = geo.lathe(f"{name}_bracts", [(-radius * 0.35, 0.0), (-radius * 0.2, radius * 0.4),
                                          (radius * 0.05, radius * 0.62), (radius * 0.1, radius * 0.5)],
                       segs=12, mat=green, axis="Z", cap1=False, sharp_angle=None)
    parts.append(bracts)
    from .util import join
    obj = join(parts, name)
    q = Vector((0, 0, 1)).rotation_difference(nrm)
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = q
    obj.location = Vector(center)
    return obj
