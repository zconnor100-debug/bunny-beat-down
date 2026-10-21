"""Unwrap the Sketchfab photoscans into clean cylindrical texture strips.

Photoscan texture atlases are fragmented, so they cannot be re-mapped onto new
geometry directly. Instead each scan is "re-skinned":

1. PCA finds the scan's symmetry axis (the most distinct principal axis), and
   the crown end (carrot top / acorn stem) is the end that is fatter nearby.
2. A proxy surface of revolution is fitted just inside the scan, following its
   bend (per-slice centroids) with UVs u = angle, v = 0 (crown) .. 1 (tip).
3. Cycles bakes scan -> proxy (selected-to-active): colour (via emission),
   tangent normals (the scan's real surface relief) and, for the acorn, roughness.
4. numpy high-passes the normal map (removes the proxy-vs-scan shape tilt so only
   surface detail remains) and evens out large-scale lighting in the colour.

Outputs in tools/_cache/weapons/derived/:
    carrot_skin_{albedo,normal}.png
    acorn_strip_{albedo,normal,rough}.png + acorn_strip.json (v of cap rim etc.)

    blender --background --python prep_scans.py
"""
from __future__ import annotations

import json
import math
import sys
from pathlib import Path

import bpy
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from bbd import bake, util  # noqa: E402

SCANS = {
    #  key           out prefix      size (u, v)    passes                    crown rule
    "carrot_scan": ("carrot_skin", (1024, 1024), ("albedo", "normal"), "fat"),    # carrot top is the fat end
    "acorn_scan": ("acorn_strip", (1024, 1024), ("albedo", "normal", "rough"), "stem"),  # acorn: stem end
}
SLICES = 72
# Calibrated mean albedo (sRGB) per scan. The carrot scan's texture is quite
# dark/red (baked shading), so its colour is rescaled per channel to a fresh
# carrot's albedo while keeping all of its natural variation.
TARGET_MEAN = {"carrot_scan": (226, 108, 30)}


def load_scan(key):
    util.reset_scene()
    bpy.ops.import_scene.gltf(filepath=str(util.CACHE / "sketchfab" / key / "model.glb"))
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    for o in meshes:
        mw = o.matrix_world.copy()
        o.parent = None
        o.matrix_world = mw
        o.data = o.data.copy()
        util.apply_transform(o)
    for o in [o for o in bpy.data.objects if o.type == "EMPTY"]:
        bpy.data.objects.remove(o)
    bpy.context.view_layer.update()
    scan = util.join(meshes, "scan")
    return scan


def analyse(scan, rule):
    n = len(scan.data.vertices)
    P = np.empty(n * 3, np.float64)
    scan.data.vertices.foreach_get("co", P)
    P = P.reshape(-1, 3)
    c = P.mean(0)
    w, V = np.linalg.eigh(np.cov((P - c).T))
    # the symmetry axis is the principal axis whose variance differs most from the others
    d = [abs(w[i] - np.mean(np.delete(w, i))) for i in range(3)]
    ax = V[:, int(np.argmax(d))]
    t = (P - c) @ ax
    edges = np.linspace(t.min(), t.max(), SLICES + 1)
    centers, radii, ts = [], [], []
    for i in range(SLICES):
        m = (t >= edges[i]) & (t < edges[i + 1])
        if m.sum() < 20:
            continue
        q = P[m] - np.outer(t[m], ax)
        cc = q.mean(0)
        rr = np.linalg.norm(q - cc, axis=1)
        centers.append(cc)
        radii.append(np.percentile(rr, 40))
        ts.append(0.5 * (edges[i] + edges[i + 1]))
    ts, radii, centers = np.array(ts), np.array(radii), np.array(centers)
    # crown end -> index 0.  'fat': the end whose quarter is fatter (carrot top);
    # 'stem': the end with the longer thin run (acorn stem vs. the short nut tip)
    q = len(ts) // 4
    if rule == "fat":
        crown_low = radii[:q].mean() > radii[-q:].mean()
    else:
        thin = radii < 0.3 * radii.max()
        crown_low = thin[:q].sum() > thin[-q:].sum()
    if not crown_low:
        ts, radii, centers = ts[::-1], radii[::-1], centers[::-1]
    # smooth centroids (follow the bend, ignore noise)
    k = np.ones(5) / 5
    cs = np.stack([np.convolve(np.pad(centers[:, j], 2, mode="edge"), k, "valid") for j in range(3)], -1)
    return c, ax, ts, radii, cs


def build_proxy(ax, ts, radii, centers, segs=96):
    import bmesh
    ax = np.asarray(ax)
    ref = np.array([0, 0, 1.0]) if abs(ax[2]) < 0.9 else np.array([1.0, 0, 0])
    u = ref - ax * ref.dot(ax)
    u /= np.linalg.norm(u)
    v = np.cross(ax, u)
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new("src")
    n = len(ts)
    keep = range(1, n - 1)  # drop the ragged end slices
    rows = []
    vs = []
    for i in keep:
        ring = []
        r = radii[i] * 0.92
        for j in range(segs):
            a = 2 * math.pi * j / segs
            p = centers[i] + ax * ts[i] + (u * math.cos(a) + v * math.sin(a)) * r
            ring.append(bm.verts.new(p.tolist()))
        rows.append(ring)
        vs.append(i)
    vmin, vmax = vs[0], vs[-1]
    for a in range(len(rows) - 1):
        A, B = rows[a], rows[a + 1]
        va = (vs[a] - vmin) / (vmax - vmin)
        vb = (vs[a + 1] - vmin) / (vmax - vmin)
        for j in range(segs):
            j1 = (j + 1) % segs
            f = bm.faces.new((A[j], A[j1], B[j1], B[j]))
            for loop, uv in zip(f.loops, ((j / segs, va), ((j + 1) / segs, va), ((j + 1) / segs, vb), (j / segs, vb))):
                loop[uvl].uv = uv
    bm.normal_update()
    # ensure outward normals
    cen = np.mean([centers[i] + ax * ts[i] for i in keep], 0)
    out = sum(1 for f in bm.faces if np.dot(np.array(f.normal), np.array(f.calc_center_median()) - cen - ax * np.dot(np.array(f.calc_center_median()) - cen, ax)) > 0)
    if out < len(bm.faces) / 2:
        bmesh.ops.reverse_faces(bm, faces=bm.faces[:])
    me = bpy.data.meshes.new("proxy")
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = True
    ob = util.new_object("proxy", me)
    return ob


def _box_blur(a, rad, axis, wrap):
    if rad < 1:
        return a
    pad = [(0, 0)] * a.ndim
    pad[axis] = (rad, rad)
    p = np.pad(a, pad, mode="wrap" if wrap else "edge")
    cs = np.cumsum(p, axis=axis, dtype=np.float64)
    cs = np.concatenate([np.zeros_like(np.take(cs, [0], axis=axis)), cs], axis=axis)
    n = a.shape[axis]
    hi = np.take(cs, np.arange(2 * rad + 1, 2 * rad + 1 + n), axis=axis)
    lo = np.take(cs, np.arange(0, n), axis=axis)
    return ((hi - lo) / (2 * rad + 1)).astype(np.float32)


def blur(a, rad):
    # x (axis 1) wraps around the circumference, y (axis 0) clamps
    for _ in range(2):
        a = _box_blur(a, rad, 1, True)
        a = _box_blur(a, rad, 0, False)
    return a


def fill_holes(img, valid):
    """Push-pull fill: grow valid pixels into ray-miss holes at increasing radii."""
    out = img.copy()
    filled = valid.copy()
    for rad in (2, 4, 8, 16, 32, 64, 128, 256):
        if filled.all():
            break
        w = filled.astype(np.float32)[..., None]
        num = blur(out * w, rad)
        den = blur(w, rad)
        new = (~filled) & (den[..., 0] > 1e-3)
        out[new] = (num / np.maximum(den, 1e-6))[new]
        filled |= new
    return out


def bake_strip(scan, proxy, prefix, size, passes, rmax):
    sc = bpy.context.scene
    util.setup_cycles(32)
    sc.render.bake.use_selected_to_active = True
    sc.render.bake.cage_extrusion = rmax * 0.35
    sc.render.bake.max_ray_distance = rmax * 0.8
    sc.render.bake.margin = 2
    mats = [s.material for s in scan.material_slots if s.material]
    for m in mats:  # make sure the scan material has the Principled named BSDF
        for nd in m.node_tree.nodes:
            if nd.type == "BSDF_PRINCIPLED":
                nd.name = "BSDF"
    pm = bpy.data.materials.new("proxy_mat")
    pm.use_nodes = True
    proxy.data.materials.append(pm)
    tgt = pm.node_tree.nodes.new("ShaderNodeTexImage")
    pm.node_tree.nodes.active = tgt
    out = {}

    def run(kind, sock=None):
        img = bpy.data.images.new(f"{prefix}_{kind}_{sock}", size[0], size[1], float_buffer=True)
        img.colorspace_settings.name = "Non-Color"
        tgt.image = img
        if sock:
            bake._rewire(mats, sock)
        util.select_only([scan, proxy], proxy)
        bpy.ops.object.bake(type=kind, use_selected_to_active=True, cage_extrusion=rmax * 0.35,
                            max_ray_distance=rmax * 0.8, margin=2, normal_space="TANGENT", use_clear=True)
        if sock:
            bake._restore(mats)
        a = bake._pixels(img)
        bpy.data.images.remove(img)
        return a

    # colour first: texels the rays never hit stay exactly black -> hole mask
    col = run("EMIT", "Base Color")[..., :3]
    valid = col.sum(-1) > 1e-6
    raw = run("NORMAL")[..., :3]
    if "albedo" in passes:
        col = fill_holes(col, valid)
        lum = col.mean(-1, keepdims=True)
        big = blur(lum, max(4, size[0] // 24))
        flat = col * np.clip(lum.mean() / np.maximum(big, 1e-4), 0.6, 1.6)
        out["albedo"] = 0.5 * col + 0.5 * flat
    if "rough" in passes:
        out["rough"] = fill_holes(run("EMIT", "Roughness")[..., :3], valid)
    if "normal" in passes:
        n = fill_holes(raw * 2 - 1, valid)
        lowf = blur(n, max(4, size[0] // 32))
        hp = n - lowf + np.array([0, 0, 1.0], np.float32)
        hp /= np.linalg.norm(hp, axis=-1, keepdims=True)
        out["normal"] = hp * 0.5 + 0.5
    out["_valid"] = valid
    return out


def main():
    util.DERIVED.mkdir(parents=True, exist_ok=True)
    for key, (prefix, size, passes, rule) in SCANS.items():
        scan = load_scan(key)
        c, ax, ts, radii, centers = analyse(scan, rule)
        rmax = float(radii.max())
        proxy = build_proxy(ax, ts, radii, centers)
        maps = bake_strip(scan, proxy, prefix, size, passes, rmax)
        maps.pop("_valid", None)
        if key in TARGET_MEAN and "albedo" in maps:
            tgt = np.array([(c / 255.0) for c in TARGET_MEAN[key]])
            tgt = np.where(tgt <= 0.04045, tgt / 12.92, ((tgt + 0.055) / 1.055) ** 2.4)
            mean = maps["albedo"].reshape(-1, 3).mean(0)
            maps["albedo"] = np.clip(maps["albedo"] * (tgt / np.maximum(mean, 1e-4)), 0, 1)
        for name, arr in maps.items():
            if name == "albedo":
                bake.save_image(f"{prefix}_{name}", bake._lin2srgb(arr), util.DERIVED / f"{prefix}_{name}.png", "PNG")
            else:
                bake.save_image(f"{prefix}_{name}", arr, util.DERIVED / f"{prefix}_{name}.png", "PNG", "Non-Color")
        info = {"radius_profile": (radii / rmax).round(3).tolist(), "length_over_radius": float((ts.max() - ts.min()) / rmax)}
        if key == "acorn_scan":
            # landmarks from the radius profile (crown first): thin stem, wide cupule,
            # a dip where the rays fall into the gap under the cupule rim, then the nut
            prof = radii[1:-1] / rmax
            n = len(prof)
            top = int(np.argmax(prof > 0.35))
            rim = top + int(np.argmax(prof[top:] > 0.9))
            rim = rim + int(np.argmax(prof[rim:] < 0.65))
            nut = rim + int(np.argmax(prof[rim:] > 0.7))
            info.update({"v_cap_top": round(top / (n - 1), 3), "v_rim": round(rim / (n - 1) - 0.02, 3),
                         "v_nut": round(nut / (n - 1) + 0.02, 3), "v_tip": 0.97})
        (util.DERIVED / f"{prefix}.json").write_text(json.dumps(info, indent=2) + "\n")
        print(prefix, json.dumps({k: v for k, v in info.items() if k != "radius_profile"}))


if __name__ == "__main__":
    main()
