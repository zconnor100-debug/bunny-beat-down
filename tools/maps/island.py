"""Wildwood Island's walk-in buildings, made in Blender: the Woodcutter's
Lodge, the Big Red Barn and the Stilt Shack.

    godot --headless --path . -s tests/export_kits.gd -- island   # -> tools/_cache/maps/raw/island/<style>.json
    blender --background --factory-startup --python tools/maps/island.py -- [lodge barn shack]
    godot --headless --import                                       # (the game sees new models after an import)

Building (src/world/building.gd) still makes every collider from its own
boxes, logs and prisms. tests/export_kits.gd records those pieces, and its
wall runs with their door and window openings, and this script builds each
one again with real detail, to the same size and in the same place: walls
of separate boards (board-and-batten on the barn, lapped siding on the
shack and the lodge's gables), stacked logs with chinking and end grain,
layered thatch with a ridge roll, slate courses, corrugated tin, a chimney
and plinths of single stones, framed doors and windows, shutters, flower
boxes, a lantern, a stovepipe and a carrot weathervane.

Materials are named "bld:<key>" and the game draws them with
Building.material(key): the same photo textures as before, tiled in metres
(every UV here is in metres; each plank board shows one plank of the
texture). Everything is built in Godot's space (Y up, +Z the front door) and
turned into Blender's as the mesh is made. Each building gets its own seed,
so its stones and boards come out the same every run.
"""
from __future__ import annotations

import json
import math
import random
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Vector, noise

sys.path.insert(0, str(Path(__file__).resolve().parent))
import models  # noqa: E402  (the shared helpers and the credits writer)

ROOT = models.ROOT
RAW = ROOT / "tools" / "_cache" / "maps" / "raw" / "island"
UP = Vector((0.0, 1.0, 0.0))

# The planks texture (2.4 m a repeat) shows five planks; where each runs
# (metres up the texture, between the seams), so a board can show just one.
PLANK_BANDS = [0.37, 0.84, 1.34, 1.81, 2.31]
PLANK_BAND_W = 0.38
BANDED = {"planks", "barn_red"}

BOARD_W = 0.32      # vertical boards (board-and-batten)
BOARD_GAP = 0.012
LAP_H = 0.3         # lapped siding: a row, and how far each overlaps the one below
LAP_OVER = 0.04
SIDING = 0.08       # how deep the siding layer is (the wall's core is the rest)
TRIM_W = 0.18       # door and window trim

SWATCH = {
    "planks": (0.55, 0.45, 0.35), "barn_red": (0.62, 0.16, 0.12), "barn_white": (0.92, 0.9, 0.85),
    "floorboards": (0.35, 0.25, 0.18), "thatch": (0.7, 0.6, 0.35), "slate_roof": (0.4, 0.42, 0.45),
    "tin_roof": (0.5, 0.3, 0.2), "bark": (0.35, 0.28, 0.2), "rock": (0.35, 0.3, 0.28),
    "stone": (0.5, 0.47, 0.44), "stone_warm": (0.55, 0.48, 0.4), "stone_cool": (0.45, 0.47, 0.5),
    "mortar": (0.6, 0.58, 0.55), "chinking": (0.86, 0.82, 0.74), "end_grain": (0.8, 0.64, 0.43),
    "iron": (0.17, 0.17, 0.19), "soot": (0.07, 0.06, 0.06), "lantern": (1.0, 0.8, 0.45),
    "carrot": (0.95, 0.45, 0.1), "leaf": (0.3, 0.6, 0.15), "plaid": (0.7, 0.3, 0.3), "soil": (0.25, 0.17, 0.11),
    "petal_red": (0.95, 0.27, 0.32), "petal_yellow": (1.0, 0.83, 0.22), "petal_white": (0.97, 0.95, 0.92),
    "petal_purple": (0.64, 0.42, 0.92),
}


def V(a) -> Vector:
    return Vector((float(a[0]), float(a[1]), float(a[2])))


def to_blender(p: Vector) -> Vector:
    """Godot (x, y, z) -> Blender (x, -z, y): a proper rotation, so faces keep their winding."""
    return Vector((p.x, -p.z, p.y))


def bmat(key: str):
    name = "bld:" + key
    m = bpy.data.materials.get(name)
    if m is None:
        m = bpy.data.materials.new(name)
        m.diffuse_color = (*SWATCH.get(key, (0.8, 0.8, 0.8)), 1.0)
    return m


# ---------------------------------------------------------------- geometry

class Group:
    """One material's geometry (Godot space, UVs in metres) and how to
    finish it: a bevel on its edges (0 for none), smooth shading below an
    angle."""

    def __init__(self, key: str, bevel: float, smooth: float):
        self.key, self.bevel, self.smooth = key, bevel, smooth
        self.verts: list[Vector] = []
        self.faces: list[tuple] = []
        self.uvs: list[list] = []


GROUPS: dict = {}


def G(key: str, bevel: float = 0.0, smooth: float = 35.0) -> Group:
    k = (key, bevel, smooth)
    if k not in GROUPS:
        GROUPS[k] = Group(key, bevel, smooth)
    return GROUPS[k]


def face_normal(ps) -> Vector:
    n = Vector((0.0, 0.0, 0.0))
    for i in range(len(ps)):
        a, b = ps[i], ps[(i + 1) % len(ps)]
        n.x += (a.y - b.y) * (a.z + b.z)
        n.y += (a.z - b.z) * (a.x + b.x)
        n.z += (a.x - b.x) * (a.y + b.y)
    return n.normalized() if n.length > 1e-12 else Vector((0.0, 1.0, 0.0))


def solid(group: Group, pts, faces, outward, uv) -> None:
    """A closed solid, welded: `faces` index `pts`; each face is wound to
    face along `outward[i]` (a vector per face); `uv` is a function of
    (point, face normal) or a list of UV lists, one per face."""
    base = len(group.verts)
    group.verts.extend(pts)
    for fi, f in enumerate(faces):
        ps = [pts[i] for i in f]
        n = face_normal(ps)
        fuv = None if callable(uv) else list(uv[fi])
        if n.dot(outward[fi]) < 0.0:
            f = tuple(reversed(f))
            ps = ps[::-1]
            n = -n
            if fuv is not None:
                fuv = fuv[::-1]
        group.faces.append(tuple(base + i for i in f))
        group.uvs.append([uv(p, n) for p in ps] if fuv is None else fuv)


def convex(group: Group, pts, faces, uv) -> None:
    c = sum(pts, Vector()) / len(pts)
    outward = [sum((pts[i] for i in f), Vector()) / len(f) - c for f in faces]
    solid(group, pts, faces, outward, uv)


BOX_FACES = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (2, 3, 7, 6), (1, 2, 6, 5), (0, 4, 7, 3)]
CORNERS = [(-1, -1, -1), (1, -1, -1), (1, 1, -1), (-1, 1, -1), (-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1)]


def box(group: Group, c: Vector, axes, half, uv) -> None:
    ax, ay, az = axes
    pts = [c + ax * (sx * half[0]) + ay * (sy * half[1]) + az * (sz * half[2]) for sx, sy, sz in CORNERS]
    convex(group, pts, BOX_FACES, uv)


def uv_box(off=(0.0, 0.0)):
    """Box projection in metres (for stones and slabs)."""
    def f(p, n):
        a = max(range(3), key=lambda i: abs(n[i]))
        if a == 1:
            return (p.x + off[0], p.z + off[1])
        if a == 0:
            return (p.z + off[0], p.y + off[1])
        return (p.x + off[0], p.y + off[1])
    return f


def uv_board(origin: Vector, centre: Vector, grain: Vector, width: float, rnd: random.Random, banded: bool, grain_v=False):
    """UVs in metres with the texture's grain along `grain`. `origin` is a
    corner of the board and `centre` its middle: across the board runs from
    the corner toward the middle, so a banded board (planks texture) shows
    one plank of it across its width. (Every face maps linearly: a face
    across the corner would smear otherwise.)"""
    off = rnd.uniform(0.0, 2.4)
    band = rnd.choice(PLANK_BANDS) if banded else rnd.uniform(0.0, 2.4)
    inward = centre - origin

    def f(p, n):
        d = p - origin
        if abs(n.dot(grain)) > 0.7:    # the board's end: a small patch of it
            a1 = n.cross(UP if abs(n.y) < 0.9 else Vector((1.0, 0.0, 0.0))).normalized()
            a2 = n.cross(a1)
            return (d.dot(a1) + off, d.dot(a2) + band)
        w = n.cross(grain)
        w = w.normalized() if w.length > 1e-6 else UP
        if w.dot(inward) < 0.0:
            w = -w
        along = d.dot(grain) + off
        across = d.dot(w)
        if banded:
            across = band + min(max(across / max(width, 1e-3), 0.0), 1.0) * min(width, PLANK_BAND_W)
        else:
            across += band
        return (across, along) if grain_v else (along, across)
    return f


def board(key: str, c: Vector, axes, half, grain_i: int, rnd: random.Random, bevel=0.012) -> None:
    """A box board, the texture's grain along axis `grain_i`."""
    grain = axes[grain_i]
    wi = max((i for i in range(3) if i != grain_i), key=lambda i: half[i])
    origin = c - axes[0] * half[0] - axes[1] * half[1] - axes[2] * half[2]
    box(G(key, bevel), c, axes, half, uv_board(origin, c, grain, 2.0 * half[wi], rnd, key in BANDED, key in ("bark", "thatch", "tin_roof")))


def frame_point(frame, u, v, d) -> Vector:
    o, U, W, O = frame
    return o + U * u + W * v + O * d


def slab_poly(group: Group, frame, poly, d_back, d_front, uv) -> None:
    """A slab: convex polygon [(u, v)] in a plane (frame: origin, U, V, O
    outward), from depth d_back to d_front along O (numbers, or functions of
    (u, v))."""
    n = len(poly)
    fb = d_back if callable(d_back) else (lambda u, v: d_back)
    ff = d_front if callable(d_front) else (lambda u, v: d_front)
    pts = [frame_point(frame, u, v, fb(u, v)) for u, v in poly] + [frame_point(frame, u, v, ff(u, v)) for u, v in poly]
    faces = [tuple(range(n)), tuple(range(n, 2 * n))] + [(i, (i + 1) % n, n + (i + 1) % n, n + i) for i in range(n)]
    convex(group, pts, faces, uv)


def clip(poly, axis: int, lo: float, hi: float):
    """The part of a convex polygon [(u, v)] with lo <= coordinate `axis` <= hi."""
    def cut(pts, keep, at):
        out = []
        for i in range(len(pts)):
            a, b = pts[i - 1], pts[i]
            if keep(b):
                if not keep(a):
                    out.append(at(a, b))
                out.append(b)
            elif keep(a):
                out.append(at(a, b))
        return out

    def at(x):
        def f(a, b):
            t = (x - a[axis]) / (b[axis] - a[axis])
            return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)
        return f
    p = cut(poly, lambda q: q[axis] >= lo - 1e-9, at(lo))
    if len(p) >= 3:
        p = cut(p, lambda q: q[axis] <= hi + 1e-9, at(hi))
    # drop repeated points
    out = []
    for q in p:
        if not out or abs(q[0] - out[-1][0]) + abs(q[1] - out[-1][1]) > 1e-5:
            out.append(q)
    if len(out) > 1 and abs(out[0][0] - out[-1][0]) + abs(out[0][1] - out[-1][1]) < 1e-5:
        out.pop()
    return out if len(out) >= 3 and poly_area(out) > 1e-4 else []


def poly_area(p) -> float:
    return abs(sum(p[i - 1][0] * p[i][1] - p[i][0] * p[i - 1][1] for i in range(len(p)))) * 0.5


def tube(group: Group, a: Vector, b: Vector, radii, segs: int, uv_len: float, rnd: random.Random | None = None,
         caps: Group | None = None, wobble=0.0, seed=0.0) -> None:
    """A round piece from a to b: `radii` is a list of radii along it (rings),
    the surface lumpy by `wobble`. The ends are capped in `caps` (end grain:
    UV = the offset from the axis), or left open when None."""
    axis = b - a
    length = axis.length
    d = axis / length
    side = d.cross(UP if abs(d.y) < 0.9 else Vector((1.0, 0.0, 0.0))).normalized()
    up = side.cross(d)
    rings = len(radii)
    pts, faces, outward, uvs = [], [], [], []
    off = rnd.uniform(0.0, 2.4) if rnd else 0.0
    for j in range(rings):
        t = j / (rings - 1)
        for i in range(segs):
            th = math.tau * i / segs
            lump = 1.0 + wobble * noise.noise(Vector((math.cos(th) * 1.4 + seed, math.sin(th) * 1.4, t * length * 0.6 + seed * 0.37)))
            pts.append(a + d * (t * length) + (side * math.cos(th) + up * math.sin(th)) * radii[j] * lump)
    r_mean = sum(radii) / rings
    for j in range(rings - 1):
        v0, v1 = j / (rings - 1) * length * uv_len + off, (j + 1) / (rings - 1) * length * uv_len + off
        for i in range(segs):
            i2 = (i + 1) % segs
            faces.append((j * segs + i, j * segs + i2, (j + 1) * segs + i2, (j + 1) * segs + i))
            th0, th1 = math.tau * i / segs, math.tau * (i + 1) / segs
            mid = (th0 + th1) * 0.5
            outward.append(side * math.cos(mid) + up * math.sin(mid))
            uvs.append([(th0 * r_mean, v0), (th1 * r_mean, v0), (th1 * r_mean, v1), (th0 * r_mean, v1)])
    solid(group, pts, faces, outward, uvs)
    if caps is not None:
        for j, sign in ((0, -1.0), (rings - 1, 1.0)):
            ring = [pts[j * segs + i] for i in range(segs)]
            centre = a + d * (j / (rings - 1) * length)
            cuv = [[((p - centre).dot(side), (p - centre).dot(up)) for p in ring]]
            solid(caps, ring, [tuple(range(segs))], [d * sign], cuv)


def ellipsoid(group: Group, c: Vector, axes, radii, segs=10, rings=6) -> None:
    ax, ay, az = axes
    pts = [c - ay * radii[1]]
    for j in range(1, rings):
        phi = math.pi * j / rings - math.pi * 0.5
        for i in range(segs):
            th = math.tau * i / segs
            pts.append(c + ax * (radii[0] * math.cos(phi) * math.cos(th)) + az * (radii[2] * math.cos(phi) * math.sin(th))
                       + ay * (radii[1] * math.sin(phi)))
    pts.append(c + ay * radii[1])
    top = len(pts) - 1
    faces = [(0, 1 + (i + 1) % segs, 1 + i) for i in range(segs)]
    for j in range(rings - 2):
        for i in range(segs):
            i2 = (i + 1) % segs
            faces.append((1 + j * segs + i, 1 + j * segs + i2, 1 + (j + 1) * segs + i2, 1 + (j + 1) * segs + i))
    last = 1 + (rings - 2) * segs
    faces += [(last + i, last + (i + 1) % segs, top) for i in range(segs)]
    outward = [sum((pts[i] for i in f), Vector()) / len(f) - c for f in faces]
    solid(group, pts, faces, outward, uv_box())


def axes_of(part):
    b = part["basis"]
    return V(b[0]), V(b[1]), V(b[2])


# ---------------------------------------------------------------- walls

def wall_pieces(length: float, height: float, openings):
    """Building._wall_pieces: the solid rectangles of a wall run with openings
    [centre along it, width, bottom, top] -> [(u0, u1, v0, v1)]."""
    cuts = [-length * 0.5, length * 0.5]
    for o in openings:
        cuts += [o[0] - o[1] * 0.5, o[0] + o[1] * 0.5]
    cuts.sort()
    pieces = []
    for a, b in zip(cuts, cuts[1:]):
        if b - a < 0.01:
            continue
        mid = (a + b) * 0.5
        spans = [[0.0, height]]
        for o in openings:
            if abs(mid - o[0]) < o[1] * 0.5:
                nxt = []
                for s in spans:
                    if o[2] > s[0]:
                        nxt.append([s[0], min(o[2], s[1])])
                    if o[3] < s[1]:
                        nxt.append([max(o[3], s[0]), s[1]])
                spans = nxt
        pieces += [(a, b, s[0], s[1]) for s in spans if s[1] - s[0] > 0.01]
    return pieces


def wall_frame(w):
    """(origin at the run's middle, y = 0; U along it; V up; O outward)."""
    a, b = V(w["a"]), V(w["b"])
    U = (b - a).normalized()
    nrm = U.cross(UP)
    mid = (a + b) * 0.5
    s = 1.0 if nrm.dot(Vector((mid.x, 0.0, mid.z))) >= 0.0 else -1.0
    return (Vector((mid.x, 0.0, mid.z)), U, UP.copy(), nrm * s)


def prism_frame(part):
    z = part["z"]
    if part["along_z"]:     # the profile in Z-Y, the prism through X at x = z
        o, U, axis = Vector((z, 0.0, 0.0)), Vector((0.0, 0.0, 1.0)), Vector((1.0, 0.0, 0.0))
    else:
        o, U, axis = Vector((0.0, 0.0, z)), Vector((1.0, 0.0, 0.0)), Vector((0.0, 0.0, 1.0))
    return (o, U, UP.copy(), axis * (1.0 if z >= 0.0 else -1.0))


def board_and_batten(key: str, frame, poly, t: float, rnd) -> None:
    """Vertical boards over a convex polygon of a wall's outer face, a batten
    over every seam (on a grid along the wall, so it runs on across pieces)."""
    us = [q[0] for q in poly]
    k0, k1 = math.floor(min(us) / BOARD_W) - 1, math.ceil(max(us) / BOARD_W) + 1
    o, U, W, O = frame
    for k in range(k0, k1):
        ua = k * BOARD_W
        part = clip(poly, 0, ua, ua + BOARD_W - BOARD_GAP)
        if part:
            origin = frame_point(frame, ua, 0.0, t * 0.5)
            centre = frame_point(frame, ua + BOARD_W * 0.5, 0.0, t * 0.5 - SIDING * 0.5)
            slab_poly(G(key, 0.012), frame, part, t * 0.5 - SIDING, t * 0.5,
                      uv_board(origin, centre, W, BOARD_W, rnd, key in BANDED))
        seam = ua - BOARD_GAP * 0.5
        bat = clip(poly, 0, seam - 0.05, seam + 0.05)
        if bat:
            origin = frame_point(frame, seam - 0.05, 0.0, t * 0.5 + 0.035)
            centre = frame_point(frame, seam, 0.0, t * 0.5 + 0.012)
            slab_poly(G(key, 0.0, 30.0), frame, bat, t * 0.5 - 0.01, t * 0.5 + 0.035, uv_board(origin, centre, W, 0.1, rnd, key in BANDED))


def lap_siding(key: str, frame, poly, t: float, rnd) -> None:
    """Lapped boards over a convex polygon of a wall's outer face: rows on a
    grid from the ground up, each one's lower edge standing out over the top
    of the row below."""
    vs = [q[1] for q in poly]
    base = t * 0.5 - SIDING
    for k in range(math.floor(min(vs) / LAP_H) - 1, math.ceil(max(vs) / LAP_H) + 1):
        lo, hi = k * LAP_H - LAP_OVER, (k + 1) * LAP_H
        part = clip(poly, 1, lo, hi)
        if not part:
            continue
        origin = frame_point(frame, 0.0, lo, t * 0.5)
        centre = frame_point(frame, 0.0, (lo + hi) * 0.5, base + 0.03)
        front = (lambda lo_, hi_: (lambda u, v: base + 0.02 + 0.06 * (hi_ - v) / (hi_ - lo_)))(lo, hi)
        slab_poly(G(key, 0.008), frame, part, base, front, uv_board(origin, centre, frame[1], LAP_H + LAP_OVER, rnd, key in BANDED))


def wall_core(key: str, frame, poly, d0: float, d1: float, grain: Vector, rnd) -> None:
    origin = frame_point(frame, 0.0, 0.0, d0)
    centre = frame_point(frame, sum(q[0] for q in poly) / len(poly), sum(q[1] for q in poly) / len(poly), (d0 + d1) * 0.5)
    slab_poly(G(key, 0.0), frame, poly, d0, d1, uv_board(origin, centre, grain, 2.4, rnd, False))


def plank_wall(w, style: str, rnd) -> None:
    frame = wall_frame(w)
    o, U, W, O = frame
    a = V(w["a"])
    t = w["thick"]
    length = (V(w["b"]) - a).length
    y0 = a.y
    battens = w["mat"] == "barn_red"
    for u0, u1, v0, v1 in wall_pieces(length, w["height"], w["openings"]):
        poly = [(u0, y0 + v0), (u1, y0 + v0), (u1, y0 + v1), (u0, y0 + v1)]
        # the core, its inside face showing bare boards (a barn is unpainted inside)
        wall_core("planks", frame, poly, -t * 0.5, t * 0.5 - SIDING, W if battens else U, rnd)
        if battens:
            board_and_batten(w["mat"], frame, poly, t, rnd)
        else:
            lap_siding(w["mat"], frame, poly, t, rnd)
    trim = "barn_white" if battens else "planks"
    for c, ow, bottom, top in w["openings"]:
        door = bottom < 0.01
        if door and battens:
            continue          # (the barn's doors have their own white frames)
        bottom += y0
        top += y0
        lo, hi = c - ow * 0.5, c + ow * 0.5
        front = (t * 0.5 - 0.02, t * 0.5 + 0.05)
        for ua, ub, va, vb in ((lo - TRIM_W, lo, bottom, top + TRIM_W), (hi, hi + TRIM_W, bottom, top + TRIM_W),
                               (lo - TRIM_W, hi + TRIM_W, top, top + TRIM_W)):
            trim_board(trim, frame, ua, ub, va, vb, front[0], front[1], rnd)
        # the reveals: thin boards lining the opening, over the cut wall
        for ua, ub, va, vb in ((lo, lo + 0.03, bottom, top), (hi - 0.03, hi, bottom, top), (lo, hi, top - 0.03, top)):
            trim_board(trim, frame, ua, ub, va, vb, -t * 0.5, t * 0.5, rnd)
        if not door:
            trim_board(trim, frame, lo - TRIM_W - 0.1, hi + TRIM_W + 0.1, bottom - 0.12, bottom, -t * 0.5, t * 0.5 + 0.16, rnd)
            shutters(w, frame, style, c, ow, bottom, top, t, rnd)


def trim_board(key: str, frame, u0, u1, v0, v1, d0, d1, rnd, bevel=0.012) -> None:
    o, U, W, O = frame
    c = frame_point(frame, (u0 + u1) * 0.5, (v0 + v1) * 0.5, (d0 + d1) * 0.5)
    half = ((u1 - u0) * 0.5, (v1 - v0) * 0.5, (d1 - d0) * 0.5)
    board(key, c, (U, W, O), half, 0 if half[0] >= half[1] else 1, rnd, bevel)


def shutters(w, frame, style: str, c, ow, bottom, top, t, rnd) -> None:
    """Shutters swung open flat against the wall beside a window: boards with
    a Z brace (red with white on the barn, bare planks on the shack, one of
    them hanging a little crooked)."""
    o, U, W, O = frame
    if style == "barn":
        sides, width, key, brace = (-1, 1), ow * 0.5, "barn_red", "barn_white"
    elif style == "shack":
        sides = (-1,) if ow < 2.4 else (-1, 1)
        width, key, brace = (1.0 if ow < 2.4 else ow * 0.5), "planks", "planks"
    else:
        return
    d0 = t * 0.5 + 0.04
    for s in sides:
        inner = c + s * (ow * 0.5 + TRIM_W)
        u_mid = inner + s * width * 0.5
        v_mid = (bottom + top) * 0.5
        tilt = math.radians(6.0) if style == "shack" and s < 0 and len(sides) == 1 else 0.0
        R = Matrix.Rotation(tilt, 3, O)
        Ux, Wx = R @ U, R @ W
        sframe = (frame_point(frame, u_mid, v_mid, 0.0), Ux, Wx, O)
        h = top - bottom
        n = max(2, round(width / 0.33))
        bw = width / n
        for i in range(n):
            u0 = -width * 0.5 + i * bw
            poly = [(u0, -h * 0.5), (u0 + bw - BOARD_GAP, -h * 0.5), (u0 + bw - BOARD_GAP, h * 0.5), (u0, h * 0.5)]
            slab_poly(G(key, 0.01), sframe, poly, d0, d0 + 0.07, uv_board(frame_point(sframe, u0, -h * 0.5, d0),
                      frame_point(sframe, u0 + bw * 0.5, 0.0, d0 + 0.035), Wx, bw, rnd, key in BANDED))
        # the Z: two rails and a diagonal
        for vr in (-h * 0.5 + 0.12, h * 0.5 - 0.12):
            p = [(-width * 0.5 + 0.04, vr - 0.09), (width * 0.5 - 0.04, vr - 0.09), (width * 0.5 - 0.04, vr + 0.09), (-width * 0.5 + 0.04, vr + 0.09)]
            slab_poly(G(brace, 0.01), sframe, p, d0 + 0.07, d0 + 0.11, uv_board(frame_point(sframe, -width * 0.5, vr - 0.09, d0 + 0.07),
                      frame_point(sframe, 0.0, vr, d0 + 0.09), Ux, 0.18, rnd, brace in BANDED))
        ua, va, ub, vb = -width * 0.5 + 0.1, -h * 0.5 + 0.22, width * 0.5 - 0.1, h * 0.5 - 0.22
        if s > 0:
            ua, ub = ub, ua
        dirv = Vector((ub - ua, vb - va))
        nrm = Vector((-dirv.y, dirv.x)).normalized() * 0.08
        p = [(ua - nrm.x, va - nrm.y), (ub - nrm.x, vb - nrm.y), (ub + nrm.x, vb + nrm.y), (ua + nrm.x, va + nrm.y)]
        slab_poly(G(brace, 0.01), sframe, p, d0 + 0.07, d0 + 0.11, uv_box((rnd.uniform(0, 2), 0)))


def log_wall(w, style: str, rnd) -> None:
    """The logs are their own pieces; here the chinking between them (a core
    inside the logs) and squared timbers framing the doors and windows over
    the cut log ends."""
    frame = wall_frame(w)
    o, U, W, O = frame
    a = V(w["a"])
    r = w["thick"] * 0.5
    length = (V(w["b"]) - a).length
    y0 = a.y
    for u0, u1, v0, v1 in wall_pieces(length, w["height"], w["openings"]):
        poly = [(u0, y0 + v0), (u1, y0 + v0), (u1, y0 + v1), (u0, y0 + v1)]
        slab_poly(G("chinking", 0.0), frame, poly, -r * 0.62, r * 0.62, uv_box())
    tw = 0.26
    deep = (-r - 0.06, r + 0.06)
    for c, ow, bottom, top in w["openings"]:
        door = bottom < 0.01
        bottom += y0
        top += y0
        lo, hi = c - ow * 0.5, c + ow * 0.5
        sill = 0.0 if door else tw
        trim_board("planks", frame, lo - tw, lo, bottom - sill, top + tw, deep[0], deep[1], rnd, 0.03)
        trim_board("planks", frame, hi, hi + tw, bottom - sill, top + tw, deep[0], deep[1], rnd, 0.03)
        trim_board("planks", frame, lo - tw, hi + tw, top, top + tw, deep[0], deep[1], rnd, 0.03)
        if not door:
            trim_board("planks", frame, lo - tw - 0.12, hi + tw + 0.12, bottom - tw, bottom, deep[0], r + 0.22, rnd, 0.03)
            if style == "lodge" and O.z > 0.9:
                flower_box(frame, lo, hi, bottom - tw, r, rnd)


def flower_box(frame, lo, hi, under, r, rnd) -> None:
    """A planter of flowers under a front window of the lodge."""
    o, U, W, O = frame
    top = under - 0.06
    bot = top - 0.42
    d0, d1 = r + 0.03, r + 0.5
    trim_board("planks", frame, lo, hi, bot, top, d1 - 0.05, d1, rnd)        # front
    trim_board("planks", frame, lo, hi, bot, bot + 0.05, d0, d1, rnd)        # bottom
    trim_board("planks", frame, lo, hi, bot, top - 0.04, d0, d0 + 0.05, rnd)  # back
    for ue in (lo, hi - 0.05):
        trim_board("planks", frame, ue, ue + 0.05, bot, top, d0, d1, rnd)
    slab_poly(G("soil"), frame, [(lo + 0.05, bot), (hi - 0.05, bot), (hi - 0.05, top - 0.07), (lo + 0.05, top - 0.07)],
              d0 + 0.05, d1 - 0.05, uv_box())
    n = int((hi - lo) / 0.26)
    for i in range(n):
        u = lo + 0.15 + (hi - lo - 0.3) * (i + rnd.uniform(0.2, 0.8)) / n
        d = rnd.uniform(d0 + 0.12, d1 - 0.12)
        h = rnd.uniform(0.18, 0.34)
        foot = frame_point(frame, u, top - 0.07, d)
        head = foot + W * h + U * rnd.uniform(-0.05, 0.05) + O * rnd.uniform(0.0, 0.06)
        tube(G("leaf", 0.0, 60.0), foot, head, [0.016, 0.012], 5, 1.0)
        ellipsoid(G(rnd.choice(["petal_red", "petal_yellow", "petal_white", "petal_purple", "petal_red"]), 0.0, 60.0),
                  head, (U, W, O), (0.09, 0.06, 0.09), 8, 4)
        leaf_at = foot + W * (h * 0.45)
        lean = (U * rnd.choice((-1.0, 1.0)) + O * 0.3).normalized()
        ellipsoid(G("leaf", 0.0, 60.0), leaf_at + lean * 0.06, (lean, W, lean.cross(W).normalized()), (0.08, 0.025, 0.035), 6, 4)


# ---------------------------------------------------------------- parts

def prism_part(part, rnd) -> None:
    frame = prism_frame(part)
    poly = [(p[0], p[1]) for p in part["pts"]]
    t = part["thick"]
    mat = part["mat"]
    if mat not in BANDED and mat != "barn_red":
        slab_poly(G(mat, 0.02), frame, poly, -t * 0.5, t * 0.5, uv_box())
        return
    battens = mat == "barn_red"
    wall_core("planks", frame, poly, -t * 0.5, t * 0.5 - SIDING, frame[2] if battens else frame[1], rnd)
    if battens:
        board_and_batten(mat, frame, poly, t, rnd)
    else:
        lap_siding(mat, frame, poly, t, rnd)


def panel(part, rnd) -> None:
    """A free-standing board piece (doors, stalls, a table top, rails):
    thin and wide ones are split into boards along their length."""
    c, size, axes = V(part["c"]), V(part["size"]), axes_of(part)
    half = [size[0] * 0.5, size[1] * 0.5, size[2] * 0.5]
    order = sorted(range(3), key=lambda i: size[i])
    thin, mid, long_ = order
    if size[thin] < 0.45 and size[mid] > 0.6:
        n = max(1, round(size[mid] / 0.3))
        bw = size[mid] / n
        for i in range(n):
            h = list(half)
            h[mid] = bw * 0.5 - BOARD_GAP * 0.5
            cc = c + axes[mid] * (-size[mid] * 0.5 + bw * (i + 0.5))
            board(part["mat"], cc, axes, h, long_, rnd)
    else:
        board(part["mat"], c, axes, half, long_, rnd)


def floor_part(part, rnd) -> None:
    c, size, axes = V(part["c"]), V(part["size"]), axes_of(part)
    half = [size[0] * 0.5, size[1] * 0.5, size[2] * 0.5]
    if size[0] * size[2] >= 80.0:
        board("floorboards", c, axes, half, 0 if size[0] >= size[2] else 2, rnd, 0.02)
        return
    # porches and ramps: separate planks across them
    n = max(1, round(size[2] / 0.3))
    bw = size[2] / n
    for i in range(n):
        cc = c + axes[2] * (-size[2] * 0.5 + bw * (i + 0.5)) + axes[1] * rnd.uniform(-0.006, 0.006)
        board("floorboards", cc, axes, (half[0] - rnd.uniform(0.0, 0.05), half[1], bw * 0.5 - 0.008), 0, rnd)


def stone_face(frame, width, v0, v1, rnd, proud=(0.03, 0.09), skip=None) -> None:
    """Courses of single stones over a face (frame at its centre, O out of
    it), from v0 to v1, each sunk 0.1 into the face."""
    o, U, W, O = frame
    v = v0
    while v < v1 - 0.12:
        h = min(rnd.uniform(0.36, 0.52), v1 - v)
        u = -width * 0.5 - rnd.uniform(0.0, 0.45)
        while u < width * 0.5:
            ln = rnd.uniform(0.48, 0.95)
            a, b = max(u, -width * 0.5 - 0.05), min(u + ln - 0.045, width * 0.5 + 0.05)
            if b - a > 0.15 and not (skip and skip((a + b) * 0.5, v + h * 0.5)):
                p = rnd.uniform(*proud)
                R = Matrix.Rotation(math.radians(rnd.uniform(-3.0, 3.0)), 3, O)
                c = frame_point(frame, (a + b) * 0.5, v + h * 0.5, p * 0.5 - 0.05)
                box(G(rnd.choice(["stone", "stone", "stone_warm", "stone_cool"]), 0.045), c, (R @ U, R @ W, O),
                    ((b - a) * 0.5, (h - 0.045) * 0.5, (p + 0.1) * 0.5), uv_box((rnd.uniform(0, 3), rnd.uniform(0, 3))))
            u += ln
        v += h


def box_faces(c: Vector, axes, half):
    """The four side faces of an upright box: (frame at the face's centre at
    y = 0, width)."""
    ax, ay, az = axes
    out = []
    for axis, other, hw, ho in ((ax, az, half[0], half[2]), (az, ax, half[2], half[0])):
        for s in (1.0, -1.0):
            O = axis * s
            U = UP.cross(O).normalized()
            centre = Vector((c.x, 0.0, c.z)) + O * hw
            out.append(((centre, U, UP.copy(), O), ho * 2.0))
    return out


def rock_part(part, style: str, rnd) -> None:
    c, size, axes = V(part["c"]), V(part["size"]), axes_of(part)
    half = (size[0] * 0.5, size[1] * 0.5, size[2] * 0.5)
    top, bottom = c.y + half[1], c.y - half[1]
    if size[1] < 4.0:
        # a plinth: a core, single stones round its top (the rest is underground)
        box(G("rock", 0.04), c, axes, half, uv_box())
        for frame, width in box_faces(c, axes, half):
            stone_face(frame, width, top - 1.0, top, rnd, (0.03, 0.07))
        return
    # the chimney: a mortar core, stones all round, a cap, and a hearth where
    # its face shows inside the lodge
    inner = (half[0] - 0.05, half[1], half[2] - 0.05)
    box(G("mortar", 0.0), c, axes, inner, uv_box())
    for frame, width in box_faces(c, axes, inner):
        o, U, W, O = frame
        indoors = O.dot(Vector((-c.x, 0.0, -c.z)).normalized()) > 0.9
        skip = (lambda u, v: abs(u) < 0.8 and v < bottom + 1.45) if indoors else None
        stone_face(frame, width, bottom, top, rnd, skip=skip)
        if indoors:
            hearth(frame, bottom, rnd)
    cap = Vector((c.x, top + 0.14, c.z))
    box(G("stone", 0.04), cap, axes, (half[0] + 0.16, 0.14, half[2] + 0.16), uv_box())
    box(G("soot"), cap + UP * 0.1, axes, (half[0] - 0.45, 0.06, half[2] - 0.45), uv_box())


def hearth(frame, floor_y, rnd) -> None:
    """The fireplace on the chimney's face inside the lodge: a sooty firebox,
    a lintel stone, a hearthstone on the floor and two logs laid ready."""
    o, U, W, O = frame
    slab_poly(G("soot"), frame, [(-0.75, floor_y), (0.75, floor_y), (0.75, floor_y + 1.3), (-0.75, floor_y + 1.3)], -0.02, 0.01, uv_box())
    lintel = frame_point(frame, 0.0, floor_y + 1.45, 0.02)
    box(G("stone_warm", 0.04), lintel, (U, W, O), (1.0, 0.16, 0.13), uv_box())
    slab_poly(G("stone", 0.03), frame, [(-1.2, floor_y), (1.2, floor_y), (1.2, floor_y + 0.1), (-1.2, floor_y + 0.1)], 0.0, 0.75, uv_box())
    for i, lean in enumerate((-0.25, 0.25)):
        a = frame_point(frame, -0.5, floor_y + 0.24 + i * 0.16, 0.12 + 0.08 * i) + U * lean * 0.3
        b = frame_point(frame, 0.5, floor_y + 0.24 + i * 0.16, 0.2 - 0.08 * i)
        tube(G("bark", 0.0, 60.0), a, b, [0.11, 0.11], 10, 1.0, rnd, G("end_grain"), 0.04, rnd.uniform(0, 50))


def log_part(part, rnd) -> None:
    a, b, r = V(part["a"]), V(part["b"]), part["r"]
    if part["mat"] != "bark":
        # (the weathervane's pole) an iron rod with a ball on top
        tube(G("iron", 0.0, 50.0), a, b, [r, r], 10, 1.0, None, G("iron", 0.0, 50.0))
        ellipsoid(G("iron", 0.0, 60.0), b, (Vector((1, 0, 0)), UP.copy(), Vector((0, 0, 1))), (0.11, 0.11, 0.11), 10, 6)
        arm_y = a + (b - a) * 0.45
        for axis in (Vector((1, 0, 0)), Vector((0, 0, 1))):
            tube(G("iron", 0.0, 50.0), arm_y - axis * 0.8, arm_y + axis * 0.8, [0.03, 0.03], 6, 1.0, None, G("iron", 0.0, 50.0))
            for s in (-1, 1):
                ellipsoid(G("iron", 0.0, 60.0), arm_y + axis * 0.8 * s, (Vector((1, 0, 0)), UP.copy(), Vector((0, 0, 1))), (0.06, 0.06, 0.06), 8, 4)
        return
    length = (b - a).length
    rings = max(2, int(length / 2.2) + 1)
    seed = rnd.uniform(0.0, 100.0)
    radii = [r * (1.0 + 0.035 * noise.noise(Vector((seed, j * 2.2, 0.5)))) for j in range(rings)]
    tube(G("bark", 0.0, 60.0), a, b, radii, 14, 1.0, rnd, G("end_grain"), 0.035, seed)


def cone_part(part, rnd) -> None:
    a, b, r = V(part["a"]), V(part["b"]), part["r"]
    if part["mat"] == "carrot":
        # a carrot: round at the top, tapering, with growth rings
        n = 14
        radii = []
        for j in range(n):
            t = j / (n - 1)
            shoulder = math.sqrt(min(1.0, t / 0.08)) if t < 0.08 else 1.0
            radii.append(max(0.004, r * shoulder * (1.0 - t) ** 0.8 * (1.0 + 0.06 * math.sin(t * math.pi * 9.0))))
        tube(G("carrot", 0.0, 70.0), a - (b - a).normalized() * 0.02, b, radii, 14, 1.0, None, G("carrot", 0.0, 70.0))
        return
    if part["mat"] == "leaf":
        d = (b - a).normalized()
        side = d.cross(UP if abs(d.y) < 0.9 else Vector((1, 0, 0))).normalized()
        for k, spread in enumerate((-0.45, 0.0, 0.45)):
            R = Matrix.Rotation(spread, 3, side.cross(d))
            dd = R @ d
            c = a + dd * (b - a).length * 0.5
            ellipsoid(G("leaf", 0.0, 60.0), c, (side, dd, side.cross(dd)), (r * 0.5, (b - a).length * 0.5, r * 0.18), 8, 6)
        return
    tube(G(part["mat"], 0.0, 50.0), a, b, [r, 0.01], 10, 1.0, None, G(part["mat"]))


def roof_frame(part):
    """(centre, along the ridge, down the slope, up out of it, length along,
    slope length, thickness)."""
    c, size, (bx, by, bz) = V(part["c"]), V(part["size"]), axes_of(part)
    if abs(bx.y) > abs(bz.y):
        s_ax, r_ax, L_s, L_r = bx, bz, size[0], size[2]
    else:
        s_ax, r_ax, L_s, L_r = bz, bx, size[2], size[0]
    down = s_ax if s_ax.y < 0.0 else -s_ax
    n_ax = by if by.y > 0.0 else -by
    return c, r_ax, down, n_ax, L_r, L_s, size[1]


def roof_point(rf, r, sigma, n) -> Vector:
    c, r_ax, down, n_ax, L_r, L_s, t = rf
    return c + r_ax * r + down * (sigma - L_s * 0.5) + n_ax * n


def courses(part, key: str, course: float, bulge: float, round_r: float, lumps: float, seg: float, rnd, bevel=0.0) -> None:
    """A roof slab laid as overlapping courses, each a little thicker at its
    lower edge (rounded for thatch), swept along the ridge."""
    rf = roof_frame(part)
    c, r_ax, down, n_ax, L_r, L_s, t = rf
    N = max(2, round(L_s / course))
    cl = L_s / N
    nr = max(1, round(L_r / seg))
    seed = rnd.uniform(0.0, 100.0)
    for i in range(N):
        s1 = (i + 1) * cl
        s0 = max(0.0, s1 - cl - 0.3)
        top1, top0 = t * 0.5 + bulge, t * 0.5 - bulge * 0.4
        prof = [(s0, -t * 0.5)]
        if round_r > 0.0:
            rb = 0.1
            rt = min(round_r, (top1 + t * 0.5) * 0.5 - 0.02)
            prof += [(s1 - rb + rb * math.cos(a), -t * 0.5 + rb + rb * math.sin(a)) for a in (-math.pi * 0.5, -math.pi * 0.25, 0.0)]
            prof += [(s1 - rt + rt * math.cos(a), top1 - rt + rt * math.sin(a)) for a in (0.0, math.pi * 0.17, math.pi * 0.33, math.pi * 0.5)]
        else:
            prof += [(s1, -t * 0.5), (s1, top1)]
        prof.append((s0, top0))
        m = len(prof)
        # the profile's length so far (the texture runs round it)
        acc = [0.0]
        for k in range(1, m + 1):
            p0, p1 = prof[k - 1], prof[k % m]
            acc.append(acc[-1] + math.hypot(p1[0] - p0[0], p1[1] - p0[1]))
        pts = []
        for j in range(nr + 1):
            r = -L_r * 0.5 + L_r * j / nr
            for k, (s, n) in enumerate(prof):
                if lumps > 0.0 and n > -t * 0.5 + 0.01:
                    n += lumps * noise.noise(Vector((r * 1.1, s * 1.3 + i * 3.7, seed)))
                    if k > 0 and s > s1 - 0.3:
                        s += lumps * 1.2 * noise.noise(Vector((r * 2.3, i * 1.9, seed + 7.0)))
                pts.append(roof_point(rf, r, s, n))
        faces, outward, uvs = [], [], []
        mid_s = (s0 + s1) * 0.5
        for j in range(nr):
            r0, r1 = -L_r * 0.5 + L_r * j / nr, -L_r * 0.5 + L_r * (j + 1) / nr
            for k in range(m):
                k2 = (k + 1) % m
                faces.append((j * m + k, j * m + k2, (j + 1) * m + k2, (j + 1) * m + k))
                cen = sum((pts[q] for q in faces[-1]), Vector()) / 4.0
                axis_pt = roof_point(rf, (r0 + r1) * 0.5, mid_s, 0.0)
                outward.append(cen - axis_pt)
                v0, v1 = acc[k], acc[k + 1]
                uvs.append([(r0, v0), (r0, v1), (r1, v1), (r1, v0)])
        # the ends (the gables' edges)
        for j, sgn in ((0, -1.0), (nr, 1.0)):
            r = -L_r * 0.5 + L_r * j / nr
            faces.append(tuple(j * m + k for k in range(m)))
            outward.append(r_ax * sgn)
            uvs.append([(s, n) for s, n in prof])
        solid(G(key, bevel, 50.0), pts, faces, outward, uvs)


def ridge_roll(a: Vector, b: Vector, rnd) -> None:
    """A thatched ridge: a fat roll along the ridge, pinned down with hazel
    liggers and criss-cross spars."""
    d = (b - a).normalized()
    seed = rnd.uniform(0.0, 100.0)
    n = max(2, int((b - a).length / 0.6))
    tube(G("thatch", 0.0, 60.0), a, b, [0.46] * (n + 1), 16, 1.0, rnd, G("thatch", 0.0, 60.0), 0.07, seed)
    side = d.cross(UP).normalized()
    for s in (-1.0, 1.0):
        low = side * (0.42 * s) + UP * -0.14
        high = side * (0.3 * s) + UP * 0.3
        for off in (low, high):
            tube(G("bark", 0.0, 60.0), a + off * 1.03, b + off * 1.03, [0.035, 0.035], 6, 1.0, rnd)
        k = 0
        x = 0.25
        while x < (b - a).length - 0.5:
            p0 = a + d * x + low * 1.05
            p1 = a + d * (x + 0.45) + high * 1.05
            if k % 2:
                p0, p1 = a + d * x + high * 1.05, a + d * (x + 0.45) + low * 1.05
            tube(G("bark", 0.0, 60.0), p0, p1, [0.025, 0.025], 5, 1.0, rnd)
            x += 0.45
            k += 1


def corrugated(part, rnd) -> None:
    """A corrugated tin roof: overlapping sheets, ribs down the slope, and
    the purlins under them."""
    rf = roof_frame(part)
    c, r_ax, down, n_ax, L_r, L_s, t = rf
    P, A, sheet = 0.16, 0.03, 1.0
    k = 0
    r0 = -L_r * 0.5
    while r0 < L_r * 0.5 - 0.05:
        r1 = min(r0 + sheet + 0.05, L_r * 0.5)
        lift = 0.012 * (k % 2) + rnd.uniform(0.0, 0.006)
        ds = rnd.uniform(-0.04, 0.04)
        ns = max(2, int((r1 - r0) / (P / 8)))
        rs = [r0 + (r1 - r0) * i / ns for i in range(ns + 1)]
        top = [t * 0.5 - 0.03 + lift + A * math.sin(math.tau * (r - r0) / P) for r in rs]
        pts = []
        for r, n in zip(rs, top):
            for s, dn in ((ds, 0.0), (L_s + ds, 0.0), (ds, -0.012), (L_s + ds, -0.012)):
                pts.append(roof_point(rf, r, s, n + dn))
        faces, outward, uvs = [], [], []
        off = rnd.uniform(0.0, 2.2)
        for i in range(ns):
            a0, a1 = i * 4, (i + 1) * 4
            u0, u1 = rs[i] + off, rs[i + 1] + off
            faces += [(a0, a1, a1 + 1, a0 + 1), (a0 + 2, a0 + 3, a1 + 3, a1 + 2), (a0, a0 + 2, a1 + 2, a1), (a0 + 1, a1 + 1, a1 + 3, a0 + 3)]
            outward += [n_ax, -n_ax, -down, down]
            uvs += [[(u0, ds), (u1, ds), (u1, L_s + ds), (u0, L_s + ds)]] * 2 + [[(u0, 0), (u0, 0.01), (u1, 0.01), (u1, 0)]] * 2
        last = ns * 4
        faces += [(0, 1, 3, 2), (last, last + 2, last + 3, last + 1)]
        outward += [-r_ax, r_ax]
        uvs += [[(0, 0), (L_s, 0), (L_s, 0.01), (0, 0.01)]] * 2
        solid(G("tin_roof", 0.0, 30.0), pts, faces, outward, uvs)
        r0 += sheet
        k += 1
    for s in (0.12, 0.5, 0.88):
        cc = roof_point(rf, 0.0, L_s * s, -t * 0.5 + 0.07)
        board("planks", cc, (r_ax, n_ax, down), (L_r * 0.5 - 0.3, 0.07, 0.07), 0, rnd)


def stovepipe(part, rnd) -> None:
    """The shack's stovepipe, up through the tin roof, with a little hat."""
    rf = roof_frame(part)
    c, r_ax, down, n_ax, L_r, L_s, t = rf
    foot = roof_point(rf, -L_r * 0.28, L_s * 0.62, 0.0)
    tube(G("iron", 0.0, 50.0), foot, foot + UP * 1.9, [0.17, 0.17], 14, 1.0, None, G("iron", 0.0, 50.0))
    tube(G("iron", 0.0, 50.0), foot + UP * 0.05, foot + UP * 0.25, [0.26, 0.2], 14, 1.0, None, G("iron", 0.0, 50.0))
    tube(G("iron", 0.0, 50.0), foot + UP * 2.0, foot + UP * 2.32, [0.36, 0.02], 14, 1.0, None, G("iron", 0.0, 50.0))
    for i in range(3):
        a = math.tau * i / 3
        off = Vector((math.cos(a), 0.0, math.sin(a))) * 0.15
        tube(G("iron", 0.0, 50.0), foot + UP * 1.85 + off, foot + UP * 2.05 + off * 1.6, [0.015, 0.015], 5, 1.0)


def lantern(part, rnd) -> None:
    """A hanging lantern on an iron bracket from the wall behind it."""
    c = V(part["c"])
    X, Z = Vector((1, 0, 0)), Vector((0, 0, 1))
    box(G("lantern"), c, (X, UP.copy(), Z), (0.13, 0.18, 0.13), uv_box())
    box(G("iron", 0.01), c - UP * 0.21, (X, UP.copy(), Z), (0.18, 0.03, 0.18), uv_box())
    for sx in (-1, 1):
        for sz in (-1, 1):
            p = c + X * (0.14 * sx) + Z * (0.14 * sz)
            box(G("iron", 0.0), p, (X, UP.copy(), Z), (0.018, 0.2, 0.018), uv_box())
    tube(G("iron", 0.0, 50.0), c + UP * 0.19, c + UP * 0.36, [0.21, 0.04], 4, 1.0, None, G("iron", 0.0, 50.0))
    prev = None
    for i in range(9):
        a = math.pi * i / 8
        p = c + UP * (0.38 + 0.11 * math.sin(a)) + X * (0.11 * math.cos(a))
        if prev is not None:
            tube(G("iron", 0.0, 50.0), prev, p, [0.014, 0.014], 5, 1.0)
        prev = p
    hook = c + UP * 0.5
    wall = Vector((c.x, hook.y, c.z - 0.66))
    tube(G("iron", 0.0, 50.0), hook, wall, [0.022, 0.022], 6, 1.0)
    tube(G("iron", 0.0, 50.0), hook, hook - UP * 0.04, [0.03, 0.03], 6, 1.0)
    box(G("iron", 0.01), wall, (X, UP.copy(), Z), (0.08, 0.14, 0.02), uv_box())


# ---------------------------------------------------------------- the buildings

def build(style: str) -> list:
    data = json.loads((RAW / f"{style}.json").read_text())
    rnd = random.Random({"lodge": 11, "barn": 23, "shack": 37}.get(style, 5))
    GROUPS.clear()
    parts, walls = data["parts"], data["walls"]
    for w in walls:
        if w["kind"] == "log":
            log_wall(w, style, rnd)
        else:
            plank_wall(w, style, rnd)
    roofs = []
    for part in parts:
        kind, mat = part["kind"], part["mat"]
        if kind == "box" and part.get("wall", -1) >= 0:
            continue                      # (built with its wall run)
        if kind == "box":
            if mat == "thatch":
                courses(part, "thatch", 1.3, 0.1, 0.2, 0.06, 0.8, rnd)
                roofs.append(part)
            elif mat == "slate_roof":
                courses(part, "slate_roof", 0.52, 0.035, 0.0, 0.0, 100.0, rnd, 0.01)
                barge(part, rnd)
                roofs.append(part)
            elif mat == "tin_roof":
                corrugated(part, rnd)
                stovepipe(part, rnd)
            elif mat == "rock":
                rock_part(part, style, rnd)
            elif mat == "floorboards":
                floor_part(part, rnd)
            elif mat in ("planks", "barn_red"):
                panel(part, rnd)
                if mat == "barn_red" and V(part["size"])[1] > 5.0:
                    door_frame(part, rnd)
            elif mat == "lantern":
                lantern(part, rnd)
            else:
                c, size, axes = V(part["c"]), V(part["size"]), axes_of(part)
                board(mat, c, axes, (size[0] * 0.5, size[1] * 0.5, size[2] * 0.5), max(range(3), key=lambda i: size[i]), rnd, 0.02)
        elif kind == "log":
            log_part(part, rnd)
        elif kind == "cone":
            cone_part(part, rnd)
        elif kind == "prism":
            prism_part(part, rnd)
    ridges(roofs, rnd)
    if style == "lodge":
        rug(data, rnd)
    if style == "shack":
        corner_posts(walls, rnd)
    return make_objects()


def door_frame(part, rnd) -> None:
    """The white frame round each leaf of the barn's big doors (its X braces
    are pieces of their own)."""
    c, size, axes = V(part["c"]), V(part["size"]), axes_of(part)
    ax, ay, az = axes
    s = 1.0 if c.dot(az) >= 0.0 else -1.0
    face = c + az * (s * 0.16)
    hx, hy = size[0] * 0.5, size[1] * 0.5
    for cc, half, g in ((face + ay * (hy - 0.15), (hx, 0.15, 0.03), 0), (face - ay * (hy - 0.15), (hx, 0.15, 0.03), 0),
                        (face + ax * (hx - 0.15), (0.15, hy - 0.3, 0.03), 1), (face - ax * (hx - 0.15), (0.15, hy - 0.3, 0.03), 1)):
        board("barn_white", cc, axes, half, g, rnd)


def ridges(roofs, rnd) -> None:
    """Where two slabs of a roof meet at the top: a thatched ridge roll, or a
    rounded cap on slate."""
    tops = []
    for part in roofs:
        rf = roof_frame(part)
        tops.append((part, rf, roof_point(rf, 0.0, 0.0, rf[6] * 0.5)))
    done = set()
    for i, (pa, ra, ta) in enumerate(tops):
        for j, (pb, rb, tb) in enumerate(tops):
            if j <= i or (i, j) in done or pa["mat"] != pb["mat"]:
                continue
            if (ta - tb).length < 1.3 and abs(ra[1].dot(rb[1])) > 0.99 and ra[2].dot(rb[2]) < 0.0:
                done.add((i, j))
                mid = (ta + tb) * 0.5
                L = max(ra[4], rb[4]) * 0.5
                a, b = mid - ra[1] * L, mid + ra[1] * L
                if pa["mat"] == "thatch":
                    ridge_roll(a - ra[1] * 0.1, b + ra[1] * 0.1, rnd)
                else:
                    tube(G(pa["mat"], 0.0, 50.0), a - UP * 0.08, b - UP * 0.08, [0.26, 0.26], 12, 1.0, rnd, G(pa["mat"], 0.0, 50.0))


def barge(part, rnd) -> None:
    """White barge boards along both gable edges of a slate strip (the barn)."""
    rf = roof_frame(part)
    c, r_ax, down, n_ax, L_r, L_s, t = rf
    for s in (-1.0, 1.0):
        cc = roof_point(rf, s * (L_r * 0.5 + 0.04), L_s * 0.5, t * 0.5 - 0.12)
        board("barn_white", cc, (down, n_ax, r_ax), (L_s * 0.5 + 0.03, 0.22, 0.04), 0, rnd)


def rug(data, rnd) -> None:
    """A plaid rug under the lodge's table."""
    fy = data["floor_y"]
    c = Vector((-3.5, fy + 0.012, -2.5))
    n = 40
    ring = [c + Vector((2.3 * math.cos(math.tau * i / n), 0.0, 1.5 * math.sin(math.tau * i / n))) for i in range(n)]
    pts = [p - UP * 0.012 for p in ring] + [p + UP * 0.012 for p in ring]
    faces = [tuple(range(n)), tuple(range(n, 2 * n))] + [(i, (i + 1) % n, n + (i + 1) % n, n + i) for i in range(n)]
    convex(G("plaid", 0.0, 40.0), pts, faces, lambda p, nn: (p.x, p.z))


def corner_posts(walls, rnd) -> None:
    """Posts over the shack's outside corners (the wall runs stop at each
    other's middles, leaving a notch)."""
    ends = []
    for w in walls:
        for e in ("a", "b"):
            ends.append((V(w[e]), w))
    seen = []
    for p, w in ends:
        for q, w2 in ends:
            if w2 is w or (p - q).length > 0.01 or any((p - s).length < 0.01 for s in seen):
                continue
            seen.append(p)
            h = min(w["height"], w2["height"])
            out = Vector((math.copysign(1.0, p.x), 0.0, math.copysign(1.0, p.z)))
            cc = Vector((p.x, p.y + h * 0.5, p.z)) + out * 0.1
            board("planks", cc, (Vector((1, 0, 0)), UP.copy(), Vector((0, 0, 1))), (0.15, h * 0.5, 0.15), 1, rnd)


def make_objects() -> list:
    objs = []
    for (key, bevel, smooth_angle), g in GROUPS.items():
        if not g.faces:
            continue
        me = bpy.data.meshes.new(key)
        me.from_pydata([tuple(to_blender(v)) for v in g.verts], [], g.faces)
        uv = me.uv_layers.new(name="UVMap")
        for poly, fuv in zip(me.polygons, g.uvs):
            for li, (u, v) in zip(poly.loop_indices, fuv):
                uv.data[li].uv = (u, 1.0 - v)     # (glTF flips V: the game gets v)
        me.validate()
        me.update()
        ob = models.link(bpy.data.objects.new(key, me))
        ob.data.materials.append(bmat(key))
        if bevel > 0.0:
            m = ob.modifiers.new("Bevel", "BEVEL")
            m.width = bevel
            m.segments = 1
            m.limit_method = "ANGLE"
            m.angle_limit = math.radians(40.0)
            m.use_clamp_overlap = True
            m.harden_normals = True
            models.apply_mods(ob)
        models.smooth(ob, smooth_angle)
        objs.append(ob)
    return objs


def main() -> None:
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    styles = [s for s in ("lodge", "barn", "shack") if not argv or s in argv]
    failed = []
    for style in styles:
        models.reset()
        try:
            models.export(f"island/{style}", build(style))
        except Exception as e:  # keep going, report at the end
            import traceback
            traceback.print_exc()
            failed.append((style, str(e)))
    models.write_credits()
    for f in failed:
        print("[island] FAILED", *f)
    if failed:
        sys.exit(1)


if __name__ == "__main__":
    main()
