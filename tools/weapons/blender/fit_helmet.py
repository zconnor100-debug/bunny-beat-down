"""Fit check: the exported acorn_helmet.glb worn by the real bun character.

Loads assets/characters/bun/bun.glb, attaches the helmet exactly as the game
does (origin at bun model space (0, 0.875, -0.010), upright, scale 1), then

1. densely samples the bun's head surface, splits it into skull vs. ears (by
   distance to the DEF_Ear bone chains) and counts samples that end up inside
   the helmet solid (nearest helmet surface faces away from the sample);
2. renders the bun wearing the helmet from the front, side, front 3/4 and
   back 3/4.

    blender --background --python fit_helmet.py -- --out DIR [--samples 64]

Writes DIR/acorn_helmet_on_bun_{front,side,front34,back34}.png and
DIR/acorn_helmet_fit.json.
"""
from __future__ import annotations

import json
import math
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

sys.path.insert(0, str(Path(__file__).resolve().parent))
from bbd import util  # noqa: E402

BUN = util.ROOT / "assets" / "characters" / "bun" / "bun.glb"
HELMET = util.OUT_PROPS / "acorn_helmet.glb"
ATTACH = Vector((0.0, 0.010, 0.875))          # glTF (0, 0.875, -0.010) in Blender axes


def args():
    a = util.script_args()
    out, samples = None, 64
    it = iter(a)
    for x in it:
        if x == "--out":
            out = Path(next(it))
        elif x == "--samples":
            samples = int(next(it))
    return out, samples


def load():
    util.reset_scene()
    bpy.ops.import_scene.gltf(filepath=str(BUN))
    bun = [o for o in bpy.data.objects]
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(HELMET))
    helmet = [o for o in bpy.data.objects if o not in before]
    for o in helmet:
        if o.parent is None:
            o.location += ATTACH
    bpy.context.view_layer.update()
    return bun, helmet


def head_samples(bun, density=2e-6, seed=0):
    body = max((o for o in bun if o.type == "MESH"), key=lambda o: len(o.data.vertices))
    me = body.data
    me.calc_loop_triangles()
    M = np.array(body.matrix_world)
    V = np.array([tuple(v.co) for v in me.vertices]) @ M[:3, :3].T + M[:3, 3]
    T = np.array([t.vertices[:] for t in me.loop_triangles])
    A, B, C = V[T[:, 0]], V[T[:, 1]], V[T[:, 2]]
    keep = np.maximum(np.maximum(A[:, 2], B[:, 2]), C[:, 2]) > ATTACH.z - 0.06
    A, B, C = A[keep], B[keep], C[keep]
    area = 0.5 * np.linalg.norm(np.cross(B - A, C - A), axis=1)
    n = np.maximum(1, (area / density).astype(int))
    idx = np.repeat(np.arange(len(A)), n)
    rng = np.random.default_rng(seed)
    u, v = rng.random(len(idx)), rng.random(len(idx))
    flip = u + v > 1
    u[flip], v[flip] = 1 - u[flip], 1 - v[flip]
    P = A[idx] + (B[idx] - A[idx]) * u[:, None] + (C[idx] - A[idx]) * v[:, None]
    # ears = near the DEF_Ear chains (from the armature itself)
    arm = next(o for o in bun if o.type == "ARMATURE")
    segs = [(np.array(arm.matrix_world @ b.head_local), np.array(arm.matrix_world @ b.tail_local))
            for b in arm.data.bones if b.name.startswith("DEF_Ear")]
    dist = np.full(len(P), 9.0)
    for a, b in segs:
        ab = b - a
        t = np.clip(((P - a) @ ab) / (ab @ ab), 0, 1)
        dist = np.minimum(dist, np.linalg.norm(P - (a + t[:, None] * ab), axis=1))
    ear = (dist < 0.045) & (P[:, 2] > ATTACH.z + 0.055)
    return P, ear


def penetration(P, helmet):
    """Inside test against the helmet surfaces.

    A sample is inside the helmet solid when it lies clearly *behind* its nearest
    helmet face: offset > 1 mm and the offset direction opposes the face normal
    (dot < -0.5). The angle test stops thin open parts (strap edges, slot rims)
    from producing false positives next to their edges.
    """
    deps = bpy.context.evaluated_depsgraph_get()
    trees = [BVHTree.FromObject(o, deps) for o in helmet if o.type == "MESH"]
    mats = [o.matrix_world for o in helmet if o.type == "MESH"]
    inside = np.zeros(len(P), bool)
    depth = np.zeros(len(P))
    gap = np.full(len(P), 9.0)
    for i, p in enumerate(P):
        best = None
        for tree, mw in zip(trees, mats):
            lp = mw.inverted() @ Vector(p)
            hit = tree.find_nearest(lp)
            if hit[0] is None:
                continue
            loc, nrm = mw @ hit[0], (mw.to_3x3() @ hit[1]).normalized()
            dd = (Vector(p) - loc).length
            if best is None or dd < best[0]:
                best = (dd, loc, nrm)
        if best:
            dd, loc, nrm = best
            gap[i] = dd
            off = Vector(p) - loc
            if dd > 0.001 and off.normalized().dot(nrm) < -0.5:
                inside[i], depth[i] = True, dd
    return inside, depth, gap


def render_views(out, samples, helmet):
    sc = bpy.context.scene
    util.setup_cycles(samples)
    sc.cycles.use_denoising = True
    sc.render.resolution_x = sc.render.resolution_y = 640
    sc.render.film_transparent = True
    sc.view_settings.view_transform = "Khronos PBR Neutral"
    w = bpy.data.worlds.new("studio")
    sc.world = w
    nt = w.node_tree
    env = nt.nodes.new("ShaderNodeTexEnvironment")
    env.image = bpy.data.images.load(util.cache_file(util.sources_meta()["studio_small_09"]["files"]["hdr"]))
    nt.links.new(env.outputs["Color"], nt.nodes["Background"].inputs["Color"])
    nt.nodes["Background"].inputs["Strength"].default_value = 0.65
    for name, loc, e in (("key", (1.6, -2.2, 2.6), 380), ("rim", (-2.0, 2.2, 2.0), 260)):
        ld = bpy.data.lights.new(name, "AREA")
        ld.energy, ld.size = e, 1.6
        lo = bpy.data.objects.new(name, ld)
        sc.collection.objects.link(lo)
        lo.location = loc
        lo.rotation_euler = (Vector((0, 0, 0.9)) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
    target = Vector((0.0, 0.0, 0.93))
    views = {"front": (0, -1, 0.08), "side": (1, 0, 0.06), "front34": (0.75, -0.8, 0.3), "back34": (-0.7, 0.75, 0.35)}
    for name, d in views.items():
        d = Vector(d).normalized()
        cd = bpy.data.cameras.new(name)
        cd.lens = 85
        cam = bpy.data.objects.new(name, cd)
        sc.collection.objects.link(cam)
        cam.location = target + d * 1.45
        cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
        sc.camera = cam
        sc.render.filepath = str(out / f"acorn_helmet_on_bun_{name}.png")
        bpy.ops.render.render(write_still=True)


def main():
    out, samples = args()
    out.mkdir(parents=True, exist_ok=True)
    if not BUN.exists():
        print("FIT skipped: no bun.glb")
        return
    bun, helmet = load()
    P, ear = head_samples(bun)
    inside, depth, gap = penetration(P, helmet)
    sk, er = ~ear, ear
    # clearance between the cranium and the helmet's inner surface (skull samples only)
    rep = {
        "samples_skull": int(sk.sum()), "samples_ear": int(er.sum()),
        "skull_inside_helmet": int((inside & sk).sum()),
        "skull_max_penetration_m": round(float(depth[inside & sk].max(initial=0.0)), 4),
        "ear_inside_helmet": int((inside & er).sum()),
        "ear_max_penetration_m": round(float(depth[inside & er].max(initial=0.0)), 4),
        "skull_min_gap_m_above_brim": round(float(gap[sk & (P[:, 2] > ATTACH.z + 0.05)].min(initial=9.0)), 4),
    }
    if (inside & sk).any():
        Q = P[inside & sk] - np.array(ATTACH)
        rep["skull_inside_where_helmet_space"] = {"x": [round(float(Q[:, 0].min()), 3), round(float(Q[:, 0].max()), 3)],
                                                 "y": [round(float(Q[:, 1].min()), 3), round(float(Q[:, 1].max()), 3)],
                                                 "z": [round(float(Q[:, 2].min()), 3), round(float(Q[:, 2].max()), 3)]}
    print("FIT", json.dumps(rep))
    (out / "acorn_helmet_fit.json").write_text(json.dumps(rep, indent=2) + "\n")
    render_views(out, samples, helmet)


if __name__ == "__main__":
    main()
