"""The acorn helmet - the hero bunny's signature item, fitted to the real `bun`.

A real acorn's anatomy turned into headgear: the upper part of the glossy nut
shell forms the bowl, the scaly cupule sits on top as an overhanging cap with
real geometric scales (tips down, shingled, the bottom row scalloping the rim),
and a woody stem nub crowns it. Brass-grommeted slots let the ears through; a
leather sweatband lines the rim and leather chin-strap tabs hang at the sides.

Fit (measured from assets/characters/bun/bun.glb, see blender/fit_helmet.py)
---------------------------------------------------------------------------
The game attaches the helmet, upright and at scale 1, with its origin at bun
model-space (0, 0.875, -0.010) [glTF]. Everything below is in *helmet space*
(Blender: +Y back, -Y front, +Z up; origin = that attach point):

* the cranium is close to a sphere: centre SKULL_C, radius 0.111 (top at
  0.969 m model space). The bowl's inner surface is that sphere grown by a
  1.5 cm clearance - a snug cartoon fit (inner diameter at the rim ~0.25 m).
* a fluffy forehead tuft sticks ~4 cm out in front at 0.864-0.919 m, so the
  bowl is tipped back TILT degrees about the skull centre: the front brim sits
  at ~0.92 m (well above the 0.855 m eyes) and the tuft peeks out under it
  like bangs, while the back brim drops to ~0.855 m.
* the ear slots are where the ear bone lines (DEF_Ear_1 -> DEF_Ear_2) leave
  the cupule, aligned with the ear direction and sized for a 0.05 x 0.03-0.04 m
  ear base plus clearance.

The bowl, cupule, scales, slots and grommets are modelled upright in *bowl
space* (axis +Z, rim centre at the origin) and mapped into helmet space by
BOWL_TO_HELMET; the chin straps are built directly in helmet space so they hang
plumb.
"""
from __future__ import annotations

import math
import random

import bmesh
import bpy
from mathutils import Matrix, Vector

from bbd import geo, mats, parts
from bbd.util import apply_modifiers

# ---- fit to bun (helmet space, Blender axes) --------------------------------------
ATTACH_GLTF = (0.0, 0.875, -0.010)            # where the game puts the origin on bun
SKULL_C = Vector((0.0, -0.026, -0.015))       # fitted cranium sphere centre
SKULL_R = 0.111
CLEAR = 0.015
RS = SKULL_R + CLEAR                          # inner surface radius
TILT = -15.0                                  # deg about X; negative lifts the front brim
H_R = 0.0285                                  # rim plane height above the sphere centre (bowl space)
BOWL_TO_HELMET = (Matrix.Translation(SKULL_C) @ Matrix.Rotation(math.radians(TILT), 4, "X")
                  @ Matrix.Translation((0.0, 0.0, H_R)))
HELMET_TO_BOWL = BOWL_TO_HELMET.inverted()


def gltf_to_helmet(p):
    """bun model-space glTF point -> helmet space (Blender axes)."""
    x, y, z = p
    return Vector((x, -(z - ATTACH_GLTF[2]), y - ATTACH_GLTF[1]))


# ear bone heads from assets/characters/bun/bun.rig.json (glTF, left side; right mirrored)
EAR_1 = (0.0590, 0.9488, -0.0400)
EAR_2 = (0.0798, 1.0144, -0.0497)
EAR_HALF = (0.033, 0.025)                     # slot half sizes: across the ear, front-back

# ---- bowl-space profile (z, r): inner pole -> inner wall -> rim lip -> nut shell ->
#      tuck -> cupule underside -> cupule rim -> cupule dome -> outer pole ------------------
R0 = math.sqrt(RS * RS - H_R * H_R)           # inner radius at the rim
_TOP_IN = RS - H_R
_INNER = [(_TOP_IN * t, math.sqrt(max(0.0, RS * RS - (_TOP_IN * t + H_R) ** 2)))
          for t in (1.0, 0.94, 0.82, 0.64, 0.44, 0.25, 0.10, 0.035)]
_LIP = [(0.0015, R0 + 0.001), (0.0, R0 + 0.004), (0.0015, R0 + 0.0075), (0.006, R0 + 0.0095)]
_SHELL = [(0.022, R0 + 0.0145), (0.038, R0 + 0.0165), (0.052, R0 + 0.0160), (0.061, R0 + 0.0135)]
_TUCK = [(0.0645, R0 + 0.0170), (0.0640, R0 + 0.0255)]
_CUP_Z, _CUP_R, _TOP = 0.0745, R0 + 0.0350, _TOP_IN + 0.033
_RIM = [(0.0665, R0 + 0.0310), (0.0700, R0 + 0.0342)]
_DOME = [(_CUP_Z + (_TOP - _CUP_Z) * math.sin(math.radians(a)), _CUP_R * math.cos(math.radians(a)))
         for a in (0, 20, 38, 54, 68, 80, 90)]
PROFILE = _INNER + _LIP + _SHELL + _TUCK + _RIM + _DOME
I_INNER_END = len(_INNER) - 1
Z_SHELL_TOP = _SHELL[-1][0]
Z_CAP_START = _TUCK[0][0]
CAP_OUTER = _RIM[-1:] + _DOME                 # used to place scales and project grommets


def cap_radius_at(z):
    """Outer cupule radius at height z (monotonic above the cupule rim)."""
    pts = CAP_OUTER
    if z <= pts[0][0]:
        return pts[0][1]
    for (z0, r0), (z1, r1) in zip(pts, pts[1:]):
        if z0 <= z <= z1:
            return r0 + (r1 - r0) * (z - z0) / max(z1 - z0, 1e-9)
    return 0.0


def inside_cap(p):
    return p.z <= _TOP and math.hypot(p.x, p.y) <= cap_radius_at(p.z)


# ---- ear slots (bowl space) ----------------------------------------------------------

def ear_slots():
    """[(side, centre on the cupule surface, axis, lateral, depth)] in bowl space."""
    out = []
    for sx in (1, -1):
        e1 = HELMET_TO_BOWL @ gltf_to_helmet((sx * EAR_1[0], EAR_1[1], EAR_1[2]))
        e2 = HELMET_TO_BOWL @ gltf_to_helmet((sx * EAR_2[0], EAR_2[1], EAR_2[2]))
        ax = (e2 - e1).normalized()
        p = e1.copy()
        for _ in range(400):           # march outward along the ear line until we leave the cap
            if not inside_cap(p):
                break
            p += ax * 0.0005
        lat = Vector((1, 0, 0)) - ax * ax.x
        lat.normalize()
        dep = ax.cross(lat).normalized()
        out.append((sx, p, ax, lat, dep))
    return out


SLOTS = ear_slots()


def in_slot(p, margin=0.0):
    for _, c, ax, lat, dep in SLOTS:
        d = p - c
        d -= ax * d.dot(ax)
        u = d.dot(lat) / (EAR_HALF[0] + margin)
        v = d.dot(dep) / (EAR_HALF[1] + margin)
        if u * u + v * v < 1.0:
            return True
    return False


# ---- parts -----------------------------------------------------------------------------

def bowl(m):
    """Closed nut+cupule solid with per-region materials and region-local src UVs."""
    obj = geo.lathe("helmet_bowl", PROFILE, segs=48, mat=m["shell"], cap0=False, cap1=False, axis="Z",
                    sharp=(I_INNER_END + 2,), sharp_angle=55)
    me = obj.data
    me.materials.append(m["cap"])
    me.materials.append(m["lining"])
    uvl = me.uv_layers["src"]
    for poly in me.polygons:
        c = poly.center
        r = math.hypot(c.x, c.y)
        if c.z > 0.003 and r < math.sqrt(max(0.0, RS * RS - (c.z + H_R) ** 2)) + 0.0015:
            poly.material_index = 2                       # inner wall: padded lining
            continue
        if c.z > Z_CAP_START - 0.0005:
            poly.material_index = 1
            lo, hi = Z_CAP_START, _TOP
        else:
            poly.material_index = 0
            lo, hi = 0.0, Z_SHELL_TOP
        for li in poly.loop_indices:
            co = me.vertices[me.loops[li].vertex_index].co
            u = uvl.data[li].uv[0]
            uvl.data[li].uv = (u, (hi - co.z) / max(hi - lo, 1e-6))   # 0 = towards the stem
    return obj


def cut_ear_slots(obj, cap_mat):
    for sx, c, ax, lat, dep in SLOTS:
        cutter = geo.lathe(f"ear_cutter{sx}", [(-0.12, 1.0), (0.12, 1.0)], segs=40, mat=cap_mat, axis="Z")
        rot = Matrix((lat, dep, ax)).transposed().to_4x4()
        cutter.matrix_world = Matrix.Translation(c) @ rot @ Matrix.Diagonal((EAR_HALF[0], EAR_HALF[1], 1.0, 1.0))
        bpy.context.view_layer.update()
        mod = obj.modifiers.new(f"ear{sx}", "BOOLEAN")
        mod.operation = "DIFFERENCE"
        mod.solver = "EXACT"
        mod.object = cutter
        apply_modifiers(obj)
        bpy.data.objects.remove(cutter)


def grommet(name, slot, mat):
    """Brass eyelet following the slot edge where it meets the cupule surface."""
    _, c, ax, lat, dep = slot
    pts = []
    for k in range(28):
        t = 2 * math.pi * k / 28
        p = c + lat * (math.cos(t) * (EAR_HALF[0] + 0.0015)) + dep * (math.sin(t) * (EAR_HALF[1] + 0.0015))
        best = p
        for step in range(80):
            q = p + ax * (-0.03 + 0.06 * step / 79)
            if inside_cap(q):
                best = q
        pts.append(best + ax * 0.0015)
    return geo.sweep(name, pts, 0.0042, segs=8, mat=mat, closed=True, flatten=0.7)


def scales(m, seed=3, rows=7, L=0.026, W=0.028):
    """Shingled cupule scales hanging tip-down; the bottom row overhangs the rim.

    Each scale is a 4 x 3 patch following the cupule surface: embedded at its
    base under the row above, bulging across, lifted and narrowing to a rounded
    tip. The two bottom rows get separate back faces (visible from below).
    src UV: u = azimuth, v = (row + local) / rows with local 0 at the base and 1
    at the tip (mats.acorn_scale). Patch winding makes front faces point out.
    """
    rng = random.Random(seed)
    prof = [Vector((r, z)) for (z, r) in CAP_OUTER]
    acc = [0.0]
    for p0, p1 in zip(prof, prof[1:]):
        acc.append(acc[-1] + (p1 - p0).length)

    def at(s):
        """(radius, z, outward normal (dr, dz)) at arc length s from the cupule rim."""
        if s <= 0.0:
            t = (prof[1] - prof[0]).normalized()
            p = prof[0] + t * s
        elif s >= acc[-1]:
            t = (prof[-1] - prof[-2]).normalized()
            p = prof[-1]
        else:
            k = max(i for i in range(len(acc) - 1) if acc[i] <= s)
            t = (prof[k + 1] - prof[k]).normalized()
            p = prof[k].lerp(prof[k + 1], (s - acc[k]) / max(acc[k + 1] - acc[k], 1e-9))
        n = Vector((t.y, -t.x))
        if n.x + n.y < 0:
            n = -n
        return p.x, p.y, n

    s_top = acc[-1] - 0.028
    s_low = -0.004 + L
    V = (0.0, 0.55, 1.0)
    U = (-1.0, -0.35, 0.35, 1.0)
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new("src")

    def emit(grid, normals, az, row, back):
        vs = [[bm.verts.new(p - n * (0.0007 if back else 0.0)) for p in rowp] for rowp, n in zip(grid, normals)]
        for a_ in range(len(V) - 1):
            for b_ in range(len(U) - 1):
                cells = [(a_, b_), (a_ + 1, b_), (a_ + 1, b_ + 1), (a_, b_ + 1)]
                if back:
                    cells.reverse()
                f = bm.faces.new([vs[i][k] for i, k in cells])
                for loop, (i, k) in zip(f.loops, cells):
                    loop[uvl].uv = (az / (2 * math.pi) + U[k] * 0.004, (row + 0.02 + 0.96 * V[i]) / rows)

    for row in range(rows):
        s_base = s_top - row * (s_top - s_low) / (rows - 1)
        r_b, _, _ = at(s_base - L * 0.5)
        n_sc = max(7, int(2 * math.pi * r_b / (W * 0.80)))
        off = rng.random()
        for j in range(n_sc):
            az = 2 * math.pi * (j + off + 0.5 * (row % 2)) / n_sc
            cdir = Vector((math.cos(az), math.sin(az), 0.0))
            adir = Vector((-math.sin(az), math.cos(az), 0.0))
            l = L * rng.uniform(0.85, 1.12)
            w = W * rng.uniform(0.85, 1.05) * (0.7 + 0.3 * min(1.0, r_b / 0.13))
            shift = rng.uniform(-0.1, 0.1) * w
            grid, normals = [], []
            for v in V:
                r, z, n2 = at(s_base - v * l)
                n3 = (cdir * n2.x + Vector((0, 0, n2.y))).normalized()
                width = w * (0.92 - 0.1 * v) * math.sqrt(max(0.0, 1.0 - v ** 3)) + w * 0.22 * v ** 4
                lift = -0.0015 + 0.0068 * v ** 1.5
                grid.append([cdir * r + Vector((0, 0, z)) + adir * (u * width * 0.5 + shift)
                             + n3 * (lift + 0.0024 * (1.0 - u * u)) for u in U])
                normals.append(n3)
            if in_slot(grid[1][1].lerp(grid[1][2], 0.5), margin=0.010) or in_slot(grid[0][1], margin=0.010):
                continue
            emit(grid, normals, az, row, back=False)
            if row >= rows - 2:
                emit(grid, normals, az, row, back=True)
    return geo.finish(bm, "cupule_scales", m["scale"], sharp_angle=None), rows


# ---- build -----------------------------------------------------------------------------

def build_acorn_helmet():
    m = {
        "shell": mats.acorn("acorn_shell", "shell", v_range=None, tint="#d08a55", rough=0.24, pale_band=0.16),
        "cap": mats.acorn("acorn_cap", "cap", tint="#7f6a52", rough=0.8),
        "scale": mats.acorn_scale(tint="#e2c8a6"),
        "lining": mats.burlap("helmet_lining", tint="#9c8664"),
        "stem": mats.acorn("acorn_stem", "cap", v_range=(0.0, 0.14), tint="#a08868", rough=0.85),
        "leather": mats.leather("leather"),
        "brass": mats.metal("brass", "brass", wear=0.6),
    }
    bowl_objs = []
    b = bowl(m)
    cut_ear_slots(b, m["cap"])
    bowl_objs.append(b)
    sc, _ = scales(m)
    bowl_objs.append(sc)
    for slot in SLOTS:
        bowl_objs.append(grommet(f"grommet{slot[0]}", slot, m["brass"]))
    stem = geo.lathe("stem", [(_TOP - 0.004, 0.0150), (_TOP + 0.006, 0.0140), (_TOP + 0.015, 0.0125),
                              (_TOP + 0.021, 0.0115), (_TOP + 0.0235, 0.0108), (_TOP + 0.0250, 0.0058),
                              (_TOP + 0.0254, 0.0)], segs=12, mat=m["stem"], cap0=True, axis="Z",
                     center_fn=lambda t: (0.0, -max(0.0, t - _TOP) * 0.25))
    geo.displace_noise(stem, 0.0011, 160.0, seed=5)
    bowl_objs.append(stem)
    band = geo.lathe("sweatband", [(0.032, R0 - 0.0005), (0.030, R0 - 0.0035), (0.006, R0 - 0.0035),
                                   (0.003, R0 - 0.0005)], segs=48, mat=m["leather"], cap0=False, cap1=False,
                     axis="Z", sharp_angle=None)
    bowl_objs.append(band)
    # stand the bowl on the bun's head
    for o in bowl_objs:
        o.matrix_world = BOWL_TO_HELMET @ o.matrix_world
    objs = list(bowl_objs)

    # chin-strap tabs: riveted to the shell flanks, hanging plumb in helmet space
    for sx in (1, -1):
        anchor = BOWL_TO_HELMET @ Vector((sx * (R0 + 0.0165), 0.0, 0.038))
        top = anchor + Vector((sx * 0.003, 0.0, 0.0))
        pts = [top + Vector((0, 0, 0.004)), top + Vector((sx * 0.001, 0.0, -0.022)),
               top + Vector((-sx * 0.004, 0.0, -0.048)), top + Vector((-sx * 0.008, 0.0, -0.072))]
        objs.append(geo.sweep(f"strap{sx}", pts, 0.0095, segs=8, mat=m["leather"], flatten=0.22, up=(sx, 0, 0)))
        objs.append(parts.rivet(f"strap_rivet{sx}", anchor + Vector((sx * 0.0045, 0, 0)), (sx, 0, 0), 0.0045,
                                m["brass"]))
        bk = top + Vector((-sx * 0.008, 0.0, -0.074))
        objs.append(geo.sweep(f"buckle{sx}", [bk + Vector((0, -0.013, 0.0)), bk + Vector((0, 0.013, 0.0)),
                                              bk + Vector((-sx * 0.001, 0.013, -0.019)),
                                              bk + Vector((-sx * 0.001, -0.013, -0.019))],
                              0.0018, segs=6, mat=m["brass"], closed=True))
        pin = geo.cylinder(f"buckle_pin{sx}", 0.0011, 0.022, 6, m["brass"], axis="Y")
        pin.location = bk + Vector((0, 0, -0.0095))
        objs.append(pin)

    markers = {}
    for sx, c, ax, lat, dep in SLOTS:
        markers["EarHole_" + ("L" if sx > 0 else "R")] = tuple(BOWL_TO_HELMET @ c)
    return {"objects": objs, "markers": markers,
            "report": {"notes": "Fitted to bun: attach with the origin at bun model space (0, 0.875, -0.010), "
                                "upright, scale 1 (opening -Y, front +Z). Inner surface = bun's cranium sphere "
                                f"(centre 2.6 cm forward of the origin) + {CLEAR * 100:.1f} cm clearance, inner "
                                f"diameter {2 * R0:.3f} m at the rim; bowl tipped back {-TILT:.0f} deg so the front "
                                "brim sits at ~0.92 m (eyes 0.855) with the forehead tuft peeking out under it. "
                                "EarHole_L/R = slot centres where the DEF_Ear_1->2 lines leave the cupule; slots "
                                f"{2 * EAR_HALF[0]:.3f} x {2 * EAR_HALF[1]:.3f} m aligned with the ears."}}


ASSETS = {
    "acorn_helmet": dict(build=build_acorn_helmet, out="props", tex=1024, kind="prop", target=0.2,
                         use="Signature acorn helmet worn by the hero bunny (attach to the head at bun model-space "
                             "(0, 0.875, -0.010))"),
}
