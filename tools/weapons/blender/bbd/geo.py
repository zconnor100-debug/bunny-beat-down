"""Procedural mesh builders (bmesh based, no operators, headless-safe).

Every builder returns a linked Blender object in metres and writes a UV map
called ``src`` that source materials may use (cylindrical for lathes / sweeps,
planar for extrusions). The final texture atlas UV (``atlas``) is created later
by bake.py, so builders never have to care about UV packing.

Conventions: lathes and sweeps are built around +Y (the barrel axis); use
``axis=`` or util.place() to orient them.
"""
from __future__ import annotations

import math
import random

import bmesh
import bpy
from mathutils import Matrix, Vector, noise

from .util import new_object

TAU = math.pi * 2.0
AXIS_ROT = {
    "Y": Matrix.Identity(4),
    "Z": Matrix.Rotation(math.radians(90), 4, "X"),    # +Y -> +Z
    "-Z": Matrix.Rotation(math.radians(-90), 4, "X"),  # +Y -> -Z
    "X": Matrix.Rotation(math.radians(-90), 4, "Z"),   # +Y -> +X
    "-X": Matrix.Rotation(math.radians(90), 4, "Z"),
    "-Y": Matrix.Rotation(math.radians(180), 4, "Z"),
}


# --------------------------------------------------------------------------- core

def _mark_sharp_by_angle(bm, angle_deg):
    lim = math.radians(angle_deg)
    for e in bm.edges:
        if len(e.link_faces) == 2 and e.calc_face_angle(0.0) > lim:
            e.smooth = False


def finish(bm, name, mat=None, smooth=True, sharp_angle=35.0, matrix=None):
    """bmesh -> linked object. Smooth shading with angle-based hard edges."""
    if matrix is not None:
        bm.transform(matrix)
    bm.normal_update()
    if smooth:
        for f in bm.faces:
            f.smooth = True
        if sharp_angle is not None:
            _mark_sharp_by_angle(bm, sharp_angle)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    obj = new_object(name, me)
    if mat is not None:
        me.materials.append(mat)
    return obj


def bevel_and_normals(obj, width, segments=2, angle=30.0, profile=0.5, weighted=True, clamp=True):
    """Hard-surface finish: angle-limited bevel + weighted normals, applied."""
    from .util import apply_modifiers
    if width > 0:
        m = obj.modifiers.new("bevel", "BEVEL")
        m.width = width
        m.segments = segments
        m.limit_method = "ANGLE"
        m.angle_limit = math.radians(angle)
        m.profile = profile
        m.use_clamp_overlap = clamp
        m.miter_outer = "MITER_ARC"
    if weighted:
        w = obj.modifiers.new("wn", "WEIGHTED_NORMAL")
        w.keep_sharp = True
        w.weight = 50
    for p in obj.data.polygons:
        p.use_smooth = True
    apply_modifiers(obj)
    return obj


# --------------------------------------------------------------------------- lathe

def lathe(name, profile, segs=24, mat=None, cap0=True, cap1=True, sharp=(), phase=0.0,
          axis="Y", sharp_angle=40.0, v_norm=False, radius_fn=None, center_fn=None, smooth=True):
    """Surface of revolution around +Y.

    profile    [(t, r), ...] positions along the axis and radii. r == 0 -> pole.
    sharp      indices of profile rings that should be hard creases.
    radius_fn  f(i, j, angle, t, r) -> r  per-vertex modulation (noise, flutes, ...)
    center_fn  f(t) -> (dx, dz)          bends the axis (organic shapes)
    v_norm     src-UV v normalised 0..1 along the profile (else metres of arc length)
    """
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new("src")
    arc = [0.0]
    for k in range(1, len(profile)):
        (t0, r0), (t1, r1) = profile[k - 1], profile[k]
        arc.append(arc[-1] + math.hypot(t1 - t0, r1 - r0))
    total = arc[-1] or 1.0
    vcoord = [a / total for a in arc] if v_norm else arc

    rings = []
    for i, (t, r) in enumerate(profile):
        cx, cz = center_fn(t) if center_fn else (0.0, 0.0)
        if r <= 1e-7:
            rings.append([bm.verts.new((cx, t, cz))])
            continue
        ring = []
        for j in range(segs):
            a = phase + TAU * j / segs
            rr = radius_fn(i, j, a, t, r) if radius_fn else r
            ring.append(bm.verts.new((cx + rr * math.cos(a), t, cz + rr * math.sin(a))))
        rings.append(ring)

    def setuv(face, uvs):
        for loop, uv in zip(face.loops, uvs):
            loop[uvl].uv = uv

    for i in range(len(rings) - 1):
        A, B = rings[i], rings[i + 1]
        va, vb = vcoord[i], vcoord[i + 1]
        for j in range(segs):
            j1 = (j + 1) % segs
            u0, u1 = j / segs, (j + 1) / segs
            if len(A) == 1 and len(B) == 1:
                continue
            if len(A) == 1:
                f = bm.faces.new((A[0], B[j], B[j1]))
                setuv(f, ((0.5 * (u0 + u1), va), (u0, vb), (u1, vb)))
            elif len(B) == 1:
                f = bm.faces.new((A[j], B[0], A[j1]))
                setuv(f, ((u0, va), (0.5 * (u0 + u1), vb), (u1, va)))
            else:
                f = bm.faces.new((A[j], B[j], B[j1], A[j1]))
                setuv(f, ((u0, va), (u0, vb), (u1, vb), (u1, va)))

    def cap(ring, outward_minus):
        if len(ring) < 3:
            return
        verts = ring if outward_minus else list(reversed(ring))
        f = bm.faces.new(verts)
        c = sum((v.co for v in ring), Vector()) / len(ring)
        rad = max((v.co - c).length for v in ring) or 1.0
        for loop in f.loops:
            d = (loop.vert.co - c) / rad
            loop[uvl].uv = (0.5 + 0.5 * d.x, 0.5 + 0.5 * d.z)
        return f

    if cap0 and len(rings[0]) > 1:
        cap(rings[0], profile[0][0] < profile[1][0])
    if cap1 and len(rings[-1]) > 1:
        cap(rings[-1], profile[-1][0] < profile[-2][0])

    bm.normal_update()
    for i in sharp:
        ring = rings[i]
        if len(ring) > 1:
            for j in range(segs):
                e = bm.edges.get((ring[j], ring[(j + 1) % segs]))
                if e:
                    e.smooth = False
    return finish(bm, name, mat, smooth=smooth, sharp_angle=sharp_angle, matrix=AXIS_ROT[axis])


def cylinder(name, r, length, segs=16, mat=None, axis="Y", center=True, bevel=0.0, **kw):
    """Capped cylinder along axis; optional rounded-edge bevel rings."""
    t0 = -length / 2 if center else 0.0
    t1 = t0 + length
    if bevel > 0:
        b = min(bevel, r * 0.5, length * 0.25)
        prof = [(t0, r - b), (t0 + b * 0.3, r - b * 0.3), (t0 + b, r),
                (t1 - b, r), (t1 - b * 0.3, r - b * 0.3), (t1, r - b)]
    else:
        prof = [(t0, r), (t1, r)]
    return lathe(name, prof, segs=segs, mat=mat, axis=axis, **kw)


def tube(name, r_out, r_in, length, segs=16, mat=None, axis="Y", lip=0.0, **kw):
    """Hollow pipe (open bore visible at both ends), rounded lips."""
    l = lip or min(0.25 * (r_out - r_in), 0.003)
    t0, t1 = 0.0, length
    prof = [(t0 + l, r_in), (t0, r_in + l), (t0, r_out - l), (t0 + l, r_out),
            (t1 - l, r_out), (t1, r_out - l), (t1, r_in + l), (t1 - l, r_in), (t0 + l, r_in)]
    # close the loop by duplicating first ring at the end -> weld afterwards
    obj = lathe(name, prof, segs=segs, mat=mat, cap0=False, cap1=False, axis=axis, **kw)
    weld(obj, 1e-6)
    return obj


def weld(obj, dist=1e-6):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=dist)
    bm.to_mesh(obj.data)
    bm.free()


# --------------------------------------------------------------------------- sweep

def _frames(pts, closed):
    n = len(pts)
    T = []
    for i in range(n):
        if closed:
            a, b = pts[(i - 1) % n], pts[(i + 1) % n]
        else:
            a, b = pts[max(i - 1, 0)], pts[min(i + 1, n - 1)]
        T.append((b - a).normalized())
    t0 = T[0]
    ref = Vector((0, 0, 1)) if abs(t0.z) < 0.9 else Vector((1, 0, 0))
    N = [(ref - t0 * ref.dot(t0)).normalized()]
    for i in range(1, n):
        q = T[i - 1].rotation_difference(T[i])
        N.append((q @ N[-1]).normalized())
    if closed and n > 2:  # distribute the holonomy twist so the seam matches
        q = T[-1].rotation_difference(T[0])
        nt = q @ N[-1]
        ang = math.atan2(T[0].dot(nt.cross(N[0])), nt.dot(N[0]))
        for i in range(n):
            N[i] = Matrix.Rotation(ang * i / n, 3, T[i]) @ N[i]
    return T, N


def sweep(name, pts, radius, segs=8, mat=None, closed=False, caps=True, sharp_angle=60.0,
          v_scale=1.0, twist=0.0, flatten=1.0, up=None):
    """Tube swept along a polyline using parallel-transport frames.

    radius  float or per-point list.  flatten < 1 squashes the section (straps).
    up      optional vector: orient the first frame's normal towards it.
    """
    pts = [Vector(p) for p in pts]
    n = len(pts)
    radii = list(radius) if isinstance(radius, (list, tuple)) else [radius] * n
    T, N = _frames(pts, closed)
    if up is not None:
        up = Vector(up)
        n0 = (up - T[0] * up.dot(T[0])).normalized()
        q = Matrix.Rotation(math.atan2(T[0].dot(N[0].cross(n0)), N[0].dot(n0)), 3, T[0])
        N = [q @ v for v in N] if not closed else N
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new("src")
    rings = []
    length = [0.0]
    for i in range(1, n):
        length.append(length[-1] + (pts[i] - pts[i - 1]).length)
    if closed:
        total_closed = length[-1] + (pts[0] - pts[-1]).length
    for i in range(n):
        B = T[i].cross(N[i])
        ring = []
        for j in range(segs):
            a = TAU * j / segs + twist * length[i]
            off = N[i] * (math.cos(a) * radii[i] * flatten) + B * (math.sin(a) * radii[i])
            ring.append(bm.verts.new(pts[i] + off))
        rings.append(ring)
    pairs = [(i, i + 1) for i in range(n - 1)] + ([(n - 1, 0)] if closed else [])
    for (ia, ib) in pairs:
        A, Bv = rings[ia], rings[ib]
        va = length[ia] * v_scale
        vb = (length[ib] if ib != 0 else total_closed) * v_scale
        for j in range(segs):
            j1 = (j + 1) % segs
            u0, u1 = j / segs, (j + 1) / segs
            f = bm.faces.new((A[j], A[j1], Bv[j1], Bv[j]))
            for loop, uv in zip(f.loops, ((u0, va), (u1, va), (u1, vb), (u0, vb))):
                loop[uvl].uv = uv
    if caps and not closed:
        for ring, rev in ((rings[0], True), (rings[-1], False)):
            f = bm.faces.new(list(reversed(ring)) if rev else ring)
            for loop in f.loops:
                loop[uvl].uv = (0.5, 0.5)
    return finish(bm, name, mat, sharp_angle=sharp_angle)


def helix(center, axis, radius, pitch, turns, pts_per_turn=16, phase=0.0):
    """Points of a helix wrapped around a line (twine / wire wraps)."""
    c = Vector(center)
    ax = Vector(axis).normalized()
    ref = Vector((0, 0, 1)) if abs(ax.z) < 0.9 else Vector((1, 0, 0))
    u = (ref - ax * ref.dot(ax)).normalized()
    v = ax.cross(u)
    n = max(2, int(turns * pts_per_turn) + 1)
    out = []
    for k in range(n):
        a = phase + TAU * turns * k / (n - 1)
        h = pitch * turns * k / (n - 1)
        out.append(c + ax * h + u * (radius * math.cos(a)) + v * (radius * math.sin(a)))
    return out


def arc_points(center, radius, a0_deg, a1_deg, n=12, plane="YZ"):
    """Points on a circular arc in a coordinate plane (trigger guards, handles)."""
    c = Vector(center)
    out = []
    for k in range(n):
        a = math.radians(a0_deg + (a1_deg - a0_deg) * k / (n - 1))
        ca, sa = math.cos(a) * radius, math.sin(a) * radius
        if plane == "YZ":
            out.append(c + Vector((0, ca, sa)))
        elif plane == "XY":
            out.append(c + Vector((ca, sa, 0)))
        else:  # XZ
            out.append(c + Vector((ca, 0, sa)))
    return out


# --------------------------------------------------------------------------- 2D outlines

def chaikin(pts, iters=3, closed=True, sharp=()):
    """Corner-cutting subdivision. Indices in `sharp` stay as hard corners."""
    P = [(Vector(p).to_2d() if len(p) >= 2 else Vector(p), i in sharp) for i, p in enumerate(pts)]
    for _ in range(iters):
        out = []
        n = len(P)
        for i in range(n):
            p, s = P[i]
            if not closed and (i == 0 or i == n - 1):
                out.append((p, True))
                continue
            if s:
                out.append((p, True))
                continue
            prv = P[(i - 1) % n][0]
            nxt = P[(i + 1) % n][0]
            out.append((p * 0.75 + prv * 0.25, False))
            out.append((p * 0.75 + nxt * 0.25, False))
        P = out
    return [tuple(p) for p, _ in P]


PLANES = {
    # plane: (A axis, B axis, N axis) with A x B = N
    "YZ": (Vector((0, 1, 0)), Vector((0, 0, 1)), Vector((1, 0, 0))),
    "XY": (Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1))),
    "XZ": (Vector((1, 0, 0)), Vector((0, 0, 1)), Vector((0, -1, 0))),
}


def extrude_outline(name, outline, thickness, mat=None, plane="YZ", offset=0.0, bevel=0.0,
                    bevel_segs=2, bevel_angle=30.0, taper=None):
    """Extrude a closed 2-D outline symmetrically along the plane normal.

    outline   [(a, b), ...] in plane coordinates (YZ: a=y, b=z = side view)
    taper     optional f(a, b) -> half-thickness multiplier (thinner toe of a stock ...)
    """
    pts = [Vector(p[:2]) for p in outline]
    area = sum(pts[i].x * pts[(i + 1) % len(pts)].y - pts[(i + 1) % len(pts)].x * pts[i].y for i in range(len(pts)))
    if area < 0:
        pts.reverse()
    A, B, N = PLANES[plane]
    h = thickness / 2
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new("src")

    def P(p, side):
        k = taper(p.x, p.y) if taper else 1.0
        return A * p.x + B * p.y + N * (offset + side * h * k)

    front = [bm.verts.new(P(p, 1)) for p in pts]
    back = [bm.verts.new(P(p, -1)) for p in pts]
    ff = bm.faces.new(front)
    fb = bm.faces.new(list(reversed(back)))
    for f in (ff, fb):
        for loop in f.loops:
            co = loop.vert.co
            loop[uvl].uv = (co.dot(A), co.dot(B))
    n = len(pts)
    per = 0.0
    for i in range(n):
        i1 = (i + 1) % n
        seg = (pts[i1] - pts[i]).length
        f = bm.faces.new((front[i], back[i], back[i1], front[i1]))
        for loop, uv in zip(f.loops, ((per, h), (per, -h), (per + seg, -h), (per + seg, h))):
            loop[uvl].uv = uv
        per += seg
    obj = finish(bm, name, mat, sharp_angle=None)
    if bevel > 0:
        bevel_and_normals(obj, bevel, bevel_segs, bevel_angle)
    return obj


def box(name, size, center=(0, 0, 0), mat=None, bevel=0.0, segs=2):
    """Axis-aligned box with optional rounded edges (weighted normals)."""
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new("src")
    bmesh.ops.create_cube(bm, size=1.0)
    sx, sy, sz = size
    for v in bm.verts:
        v.co = Vector((v.co.x * sx + center[0], v.co.y * sy + center[1], v.co.z * sz + center[2]))
    bm.normal_update()
    for f in bm.faces:  # simple planar src UVs (metres)
        nrm = f.normal
        for loop in f.loops:
            co = loop.vert.co
            if abs(nrm.x) > 0.5:
                loop[uvl].uv = (co.y, co.z)
            elif abs(nrm.y) > 0.5:
                loop[uvl].uv = (co.x, co.z)
            else:
                loop[uvl].uv = (co.x, co.y)
    obj = finish(bm, name, mat, sharp_angle=None)
    if bevel > 0:
        bevel_and_normals(obj, bevel, segs)
    else:
        for p in obj.data.polygons:
            p.use_smooth = False
    return obj


# --------------------------------------------------------------------------- organics

def displace_noise(obj, strength, scale, seed=0, axis_mask=(1, 1, 1)):
    """Push vertices along their normals by Perlin noise (organic irregularity)."""
    me = obj.data
    off = Vector((seed * 13.1, seed * 7.7, seed * 3.3))
    for v in me.vertices:
        d = noise.noise(v.co * scale + off) * strength
        n = v.normal
        v.co += Vector((n.x * axis_mask[0], n.y * axis_mask[1], n.z * axis_mask[2])) * d
    me.update()


def carrot_profile(length, radius, rings=12, shoulder=0.08, tip=0.06, power=1.15, crown=0.35):
    """Lathe profile (t along +Y from tip at t=0 to crown at t=length).

    Carrots taper to a point; the tip end sits at t=0 so the carrot "points" -Y
    in builder space. Use flip/rotate as needed. Returns [(t, r)].
    """
    prof = [(0.0, 0.0)]
    for k in range(1, rings + 1):
        s = k / rings                       # 0 at tip .. 1 at crown
        taper = s ** (1.0 / power)
        shoulder_k = 1.0
        if s > 1.0 - shoulder:              # rounded shoulder near the crown
            q = (s - (1.0 - shoulder)) / shoulder
            shoulder_k = math.sqrt(max(0.0, 1.0 - q * q * 0.55))
        r = radius * max(tip, taper) * shoulder_k
        prof.append((s * length, r))
    # crown: slightly domed top with a small dimple where the greens sprout
    r_top = prof[-1][1]
    prof.append((length + r_top * 0.06, r_top * 0.75))
    prof.append((length + r_top * 0.08, r_top * crown))
    prof.append((length + r_top * 0.04, 0.0))
    return prof


def carrot(name, length, radius, segs=12, rings=10, mat=None, seed=0, bend=0.0, bumps=0.06,
           crown_mat=None, tip_round=0.06, power=1.15):
    """A whole carrot pointing along -Y (tip at origin side, crown at +Y end).

    src UV: u around, v normalised from crown (0) to tip (1) to match the
    unwrapped photoscan strip (see prep_scans.py).
    """
    rng = random.Random(seed)
    prof = carrot_profile(length, radius, rings=rings, tip=tip_round, power=power)
    phase = rng.random() * TAU
    off = Vector((seed * 1.7, seed * 2.9, 0.0))

    def rfn(i, j, a, t, r):
        if bumps <= 0:
            return r
        n = noise.noise(Vector((math.cos(a) * 2.0, t / max(length, 1e-6) * 6.0, math.sin(a) * 2.0)) + off)
        rings_k = 0.5 + 0.5 * math.sin(t / max(length, 1e-6) * 38.0 + seed)  # faint growth rings
        return r * (1.0 + bumps * n + bumps * 0.25 * rings_k)

    def cfn(t):
        s = t / max(length, 1e-6)
        return (bend * length * (1 - s) ** 2 * 0.5, bend * length * (1 - s) ** 2 * 0.2)

    obj = lathe(name, prof, segs=segs, mat=mat, cap0=False, cap1=False, phase=phase,
                v_norm=True, radius_fn=rfn, center_fn=cfn if bend else None, sharp_angle=None)
    # flip v so that 0 = crown, 1 = tip (strip convention)
    for l in obj.data.uv_layers["src"].data:
        l.uv = (l.uv[0], 1.0 - l.uv[1])
    return obj


def leaflet_outline(n_lobes=3, width=0.32):
    """A deeply-divided carrot leaflet outline in unit space (along +x, 0..1).

    Narrow pointed lobes with incisions almost to the midrib give the lacy,
    parsley-like look of real carrot tops.
    """
    def lobe(k):
        w = width * (1.0 - 0.5 * k / n_lobes)
        return (k + 0.12) / n_lobes, (k + 0.85) / n_lobes, w
    pts = [(0.0, 0.0)]
    for k in range(n_lobes):
        x_in, x_tip, w = lobe(k)
        pts.append((x_in, w * 0.10))
        pts.append((x_tip, w))
    pts.append((1.0, 0.0))
    for k in reversed(range(n_lobes)):
        x_in, x_tip, w = lobe(k)
        pts.append((x_tip, -w))
        pts.append((x_in, -w * 0.10))
    return pts


def carrot_greens(name, length=0.1, stems=3, spread=28.0, pairs=4, lobes=3, seed=0, mat=None,
                  stem_mat=None, stem_r=0.0018, droop=0.25, stem_segs=4, leaf_scale=1.0,
                  direction=(0, 0, 1), leaf_width=0.38):
    """Feathery carrot-top sprig sprouting from the origin along `direction`.

    Real geometry (stems are thin swept tubes, leaflets are two-sided folded
    cards) so it survives without alpha textures. Triangle cost roughly
    stems * (stem_segs*6 + (2*pairs+1) * (2*lobes+1) * 2).
    """
    rng = random.Random(seed)
    up = Vector(direction).normalized()
    ref = Vector((1, 0, 0)) if abs(up.x) < 0.9 else Vector((0, 1, 0))
    side0 = (ref - up * ref.dot(up)).normalized()
    parts = []
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new("src")
    outline = leaflet_outline(lobes, leaf_width)
    for s in range(stems):
        az = TAU * s / stems + rng.uniform(-0.4, 0.4)
        tilt = math.radians(spread * rng.uniform(0.6, 1.2))
        L = length * rng.uniform(0.75, 1.1)
        side = Matrix.Rotation(az, 3, up) @ side0
        d0 = (up * math.cos(tilt) + side * math.sin(tilt)).normalized()
        # stem polyline: rises then droops outward
        pts = []
        for k in range(6):
            q = k / 5
            p = d0 * (q * L) + side * (droop * L * q * q * 0.6) - up * (droop * L * q * q * 0.5)
            pts.append(p)
        stem = sweep(f"{name}_stem{s}", pts, [stem_r * (1 - 0.6 * k / 5) for k in range(6)],
                     segs=stem_segs, mat=stem_mat or mat, caps=False)
        parts.append(stem)
        # leaflets along the upper part of the stem
        n_leaf = 2 * pairs + 1
        for k in range(n_leaf):
            if k == n_leaf - 1:
                q, sgn = 1.0, 0
            else:
                q = 0.35 + 0.6 * (k // 2) / max(1, pairs)
                sgn = 1 if k % 2 == 0 else -1
            seg_i = min(4, int(q * 5))
            frac = q * 5 - seg_i
            base = pts[seg_i].lerp(pts[min(seg_i + 1, 5)], frac)
            tdir = (pts[min(seg_i + 1, 5)] - pts[seg_i]).normalized()
            lat = tdir.cross(up)
            if lat.length < 1e-4:
                lat = side.cross(tdir)
            lat.normalize()
            if sgn == 0:
                ldir = tdir
            else:
                ldir = (lat * sgn * 0.8 + tdir * 0.6 + up * 0.15).normalized()
            size = L * 0.32 * leaf_scale * (1.15 - 0.5 * q)
            norm = ldir.cross(lat if sgn else side).normalized()
            if norm.dot(up) < 0:
                norm = -norm
            width_dir = norm.cross(ldir).normalized()
            fold = 0.18 * size
            for side_k in (1, -1):  # two-sided card (offset slightly)
                vs = []
                for (x, y) in outline:
                    p = base + ldir * (x * size) + width_dir * (y * size) + norm * (fold * (0.25 - abs(y)) * 0.6)
                    p += norm * (0.0002 * side_k)
                    vs.append(bm.verts.new(p))
                f = bm.faces.new(vs if side_k > 0 else list(reversed(vs)))
                for loop, (x, y) in zip(f.loops, outline if side_k > 0 else list(reversed(outline))):
                    loop[uvl].uv = (x, 0.5 + y)
    bmesh.ops.triangulate(bm, faces=bm.faces[:], quad_method="BEAUTY", ngon_method="EAR_CLIP")
    leaves = finish(bm, f"{name}_leaves", mat, sharp_angle=None)
    parts.append(leaves)
    from .util import join
    return join(parts, name)


def pinnate_leaf(name, base, direction, normal, length, pairs=4, lobes=3, leaf_width=0.38, mat=None,
                 stem_mat=None, stem_r=0.0018, curl=0.12, leaflet_scale=0.34, stem_segs=5):
    """A flat compound (pinnate) carrot leaf lying in the plane with the given normal.

    Used for the leafy fins of the rocket carrot and pickup garnish. Two-sided cards.
    """
    from .util import join
    d = Vector(direction).normalized()
    nrm = Vector(normal)
    nrm = (nrm - d * nrm.dot(d)).normalized()
    side = d.cross(nrm).normalized()
    base = Vector(base)
    L = length
    rib = [base + d * (L * q) + nrm * (curl * L * q * q) for q in (0, 0.2, 0.4, 0.6, 0.8, 1.0)]
    stem = sweep(f"{name}_rib", rib, [stem_r * (1 - 0.7 * k / 5) for k in range(6)], segs=stem_segs,
                 mat=stem_mat or mat, caps=False, up=nrm)
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new("src")
    outline = leaflet_outline(lobes, leaf_width)
    specs = []
    for k in range(pairs):
        q = 0.22 + 0.7 * k / max(1, pairs)
        for sgn in (1, -1):
            specs.append((q, sgn))
    specs.append((1.0, 0))
    for q, sgn in specs:
        i = min(4, int(q * 5))
        f = q * 5 - i
        p0 = rib[i].lerp(rib[min(i + 1, 5)], f)
        tdir = (rib[min(i + 1, 5)] - rib[i]).normalized()
        ldir = tdir if sgn == 0 else (side * sgn * 0.8 + tdir * 0.6).normalized()
        wdir = nrm.cross(ldir).normalized()
        size = L * leaflet_scale * (1.15 - 0.55 * q)
        for sk in (1, -1):
            vs = []
            for (x, y) in outline:
                p = p0 + ldir * (x * size) + wdir * (y * size) + nrm * (0.12 * size * (0.25 - abs(y)) + 0.00025 * sk)
                vs.append(bm.verts.new(p))
            ol = outline if sk > 0 else list(reversed(outline))
            fc = bm.faces.new(vs if sk > 0 else list(reversed(vs)))
            for loop, (x, y) in zip(fc.loops, ol):
                loop[uvl].uv = (x, 0.5 + y)
    bmesh.ops.triangulate(bm, faces=bm.faces[:], quad_method="BEAUTY", ngon_method="EAR_CLIP")
    leaves = finish(bm, f"{name}_leaflets", mat, sharp_angle=None)
    return join([stem, leaves], name)


def bend_yz(obj, radius):
    """Bend a mesh laid out along +Y (from y = 0) into an arc of `radius` curving toward +Z.

    Vertices keep their distance from the neutral axis, so cross-sections stay round.
    """
    me = obj.data
    for v in me.vertices:
        x, y, z = v.co
        th = y / radius
        v.co = Vector((x, (radius - z) * math.sin(th), radius - (radius - z) * math.cos(th)))
    me.update()
    return obj
