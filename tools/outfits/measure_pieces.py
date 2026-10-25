"""Measure where the head goes in every outfit model and write
src/critters/outfit_shapes.gd (runs inside Blender):

    blender -b --factory-startup --python tools/outfits/measure_pieces.py

A hat's bounding box says little about where it sits: a cap's visor, a
cavalier's turned-up brim or an archer's swept tip pull the middle of the
box off the crown, and its lowest point (a visor's tip, a brim) is not where
its rim is. So rays are cast up into each model from below, on a grid. Under
a brim or a visor they hit low; inside the crown they hit the inside of the
top, high up. The biggest patch of high hits is the hole the head goes into:
its middle, its width each way, the height of its rim (where the crown's wall
ends: the lowest hits right round the hole) and of the inside of its top.
Open rings (a crown, a flower crown, a sweatband) have no inside top: the rays
go straight through, and the hole is the empty patch the ring encloses.

From the front (rays along -Z) every model also gets the middle and width of
what you see of it, and from the side (rays along -X) its front and back at
each height: glasses, masks, capes and packs are placed by those.

Everything is in Godot's frame (+Y up, the model's own +Z ahead), in the units
the env pipeline built it in (the hat is scaled to fit at run time).
"""
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "src" / "critters" / "outfit_shapes.gd"
N = 64


def load(path: Path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(path))
    verts, tris = [], []
    dg = bpy.context.evaluated_depsgraph_get()
    for o in bpy.context.scene.objects:
        if o.type != "MESH":
            continue
        me = o.evaluated_get(dg).to_mesh()
        me.calc_loop_triangles()
        base = len(verts)
        for v in me.vertices:
            w = o.matrix_world @ v.co
            verts.append(Vector((w.x, w.z, -w.y)))   # Blender Z-up -> Godot Y-up
        for t in me.loop_triangles:
            tris.append(tuple(base + i for i in t.vertices))
        o.evaluated_get(dg).to_mesh_clear()
    return verts, tris


def heights(tree, lo, hi, up: bool):
    """First hit on a ray from below (up=True) or from above, per grid cell."""
    h = hi.y - lo.y
    grid = []
    for i in range(N):
        for j in range(N):
            x = lo.x + (hi.x - lo.x) * (i + 0.5) / N
            z = lo.z + (hi.z - lo.z) * (j + 0.5) / N
            if up:
                loc, *_ = tree.ray_cast(Vector((x, lo.y - 1.0, z)), Vector((0, 1, 0)), h + 2.0)
            else:
                loc, *_ = tree.ray_cast(Vector((x, hi.y + 1.0, z)), Vector((0, -1, 0)), h + 2.0)
            grid.append(loc.y if loc is not None else None)
    return grid


def from_below(tree, lo, hi):
    """The head-hole: an open ring's empty middle; a hollow hat's inside (high
    hits from below); or a closed one's crown (high hits from above)."""
    h = hi.y - lo.y
    below = heights(tree, lo, hi, True)
    above = heights(tree, lo, hi, False)
    kind = "ring"
    comp = enclosed(below)
    if len(comp) < N * N * 0.03:
        kind = "hollow"
        comp = largest(below, lambda v: v is not None and v > lo.y + h * 0.12)
        if len(comp) < N * N * 0.03:
            kind = "closed"
            comp = largest(above, lambda v: v is not None and v > lo.y + h * 0.3)
    if len(comp) < 4:
        return {}
    xs = [lo.x + (hi.x - lo.x) * (c // N + 0.5) / N for c in comp]
    zs = [lo.z + (hi.z - lo.z) * (c % N + 0.5) / N for c in comp]
    cell_x, cell_z = (hi.x - lo.x) / N, (hi.z - lo.z) / N
    inside = set(comp)
    # the rim: the lowest hits from below right round the hole (a closed hat's
    # crown: its own underside)
    rims = []
    for c in comp:
        i, j = divmod(c, N)
        for di, dj in ((1, 0), (-1, 0), (0, 1), (0, -1), (2, 0), (-2, 0), (0, 2), (0, -2)):
            ii, jj = i + di, j + dj
            if 0 <= ii < N and 0 <= jj < N:
                k = ii * N + jj
                if (k not in inside or kind == "closed") and below[k] is not None:
                    rims.append(below[k])
    rims.sort()
    tops = [below[c] for c in comp if below[c] is not None] if kind == "hollow" else [above[c] for c in comp if above[c] is not None]
    xs.sort()
    zs.sort()
    return {
        "hole": [sum(xs) / len(xs), sum(zs) / len(zs)],
        "w": xs[-1] - xs[0] + cell_x, "d": zs[-1] - zs[0] + cell_z,
        "rim": rims[len(rims) // 4] if rims else lo.y,
        "top": max(tops) if tops else hi.y,
        "open": kind == "ring",
    }


def from_front(tree, lo, hi):
    """What you see from the front (+Z): its middle and width."""
    xs, ys = [], []
    for i in range(N):
        for j in range(N):
            x = lo.x + (hi.x - lo.x) * (i + 0.5) / N
            y = lo.y + (hi.y - lo.y) * (j + 0.5) / N
            loc, *_ = tree.ray_cast(Vector((x, y, hi.z + 1.0)), Vector((0, 0, -1)), hi.z - lo.z + 2.0)
            if loc is not None:
                xs.append(x)
                ys.append(y)
    if not xs:
        return {}
    xs.sort()
    return {"face": [sum(xs) / len(xs), sum(ys) / len(ys)], "fw": xs[int(len(xs) * 0.98)] - xs[int(len(xs) * 0.02)]}


def largest(grid, ok):
    seen, best = set(), []
    for start in range(len(grid)):
        if start in seen or not ok(grid[start]):
            continue
        comp, stack = [], [start]
        seen.add(start)
        while stack:
            c = stack.pop()
            comp.append(c)
            i, j = divmod(c, N)
            for di, dj in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                ii, jj = i + di, j + dj
                if 0 <= ii < N and 0 <= jj < N:
                    k = ii * N + jj
                    if k not in seen and ok(grid[k]):
                        seen.add(k)
                        stack.append(k)
        if len(comp) > len(best):
            best = comp
    return best


def enclosed(grid):
    """Empty cells a ring of hits closes in (not reachable from the edge)."""
    outside, stack = set(), []
    for i in range(N):
        for j in range(N):
            if (i in (0, N - 1) or j in (0, N - 1)) and grid[i * N + j] is None:
                outside.add(i * N + j)
                stack.append(i * N + j)
    while stack:
        c = stack.pop()
        i, j = divmod(c, N)
        for di, dj in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ii, jj = i + di, j + dj
            if 0 <= ii < N and 0 <= jj < N:
                k = ii * N + jj
                if k not in outside and grid[k] is None:
                    outside.add(k)
                    stack.append(k)
    return [c for c in range(len(grid)) if grid[c] is None and c not in outside]


def fmt(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, list):
        return "[" + ", ".join("%.4f" % x for x in v) + "]"
    return "%.4f" % v


def main():
    lines = []
    for d in sorted((ROOT / "assets" / "env").glob("outfit_*")):
        pid = d.name[len("outfit_"):]
        glb = d / f"{d.name}.glb"
        if not glb.exists():
            continue
        verts, tris = load(glb)
        if not tris:
            print("SKIP", pid)
            continue
        lo = Vector((min(v.x for v in verts), min(v.y for v in verts), min(v.z for v in verts)))
        hi = Vector((max(v.x for v in verts), max(v.y for v in verts), max(v.z for v in verts)))
        tree = BVHTree.FromPolygons(verts, tris, all_triangles=True)
        m = {"box": [lo.x, lo.y, lo.z, hi.x, hi.y, hi.z]}
        m.update(from_below(tree, lo, hi))
        m.update(from_front(tree, lo, hi))
        body = ", ".join(f'"{k}": {fmt(v)}' for k, v in m.items())
        lines.append(f'\t"{pid}": {{{body}}},')
        print("MEASURED", pid, body)
    OUT.write_text('''class_name OutfitShapes
extends RefCounted
## Where the head goes in each outfit model, measured by
## tools/outfits/measure_pieces.py (generated: run it again after adding or
## rebuilding a piece). In the model's own frame (+Y up, +Z its front):
##   box: [min x, min y, min z, max x, max y, max z] of the whole model;
##   hole: [x, z] middle of the head-hole seen from below, w: its width across
##   x, d: its depth along z, rim: height of its rim (where the crown's wall
##   ends), top: height of the inside of the top, open: a ring with no top;
##   face: [x, y] middle of the model seen from the front, fw: its width there.

const SHAPES := {
%s
}
''' % "\n".join(lines))
    print("WROTE", OUT, len(lines))


main()
