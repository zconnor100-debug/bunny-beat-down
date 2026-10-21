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
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
from bbd import bake, util  # noqa: E402

SCANS = {
    #  key           out prefix      size (u, v)    passes                    crown rule
    "carrot_scan": ("carrot_skin", (1024, 1024), ("albedo", "normal"), "fat"),    # carrot top is the fat end
    "acorn_scan": ("acorn_strip", (1024, 1024), ("albedo", "normal", "rough"), "stem"),  # acorn: stem end
    "tulip_scan": ("tulip_strip", (1024, 1024), ("albedo", "normal"), "fat"),      # flower end (v = 0) vs stem
}
SLICES = 72
# Calibrated mean albedo (sRGB) per scan. The carrot scan's texture is quite
# dark/red (baked shading), so its colour is rescaled per channel to a fresh
# carrot's albedo while keeping all of its natural variation.
TARGET_MEAN = {"carrot_scan": (226, 108, 30)}

# Top-down planar re-skins (leaves, mushroom cap): key -> (prefix, px, frame rule)
#   "pca": project along the scan's thinnest axis, long axis -> image v, stalk end at v = 0
#   "up":  look straight down Blender -Z (object scanned upright)
PLANAR = {
    "maple_leaf_scan": ("maple_leaf", 1024, "pca"),
    "oak_leaf": ("oak_leaf", 1024, "pca"),
    "parasol_scan": ("parasol_cap", 1024, "up"),
}


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


def _emit_const(mats, rgb):
    """Route a constant colour to the output (coverage pass); undo with bake._restore."""
    for m in mats:
        nt = m.node_tree
        em = nt.nodes.new("ShaderNodeEmission")
        em.name = "BAKE_EMIT"
        em.inputs["Color"].default_value = (*rgb, 1.0)
        nt.links.new(em.outputs[0], bake._output(nt).inputs["Surface"])


def _save_rgba(name, rgba, path):
    img = bpy.data.images.new(name, rgba.shape[1], rgba.shape[0], alpha=True)
    img.alpha_mode = "STRAIGHT"
    img.pixels.foreach_set(np.clip(rgba, 0, 1).astype(np.float32).ravel())
    img.file_format = "PNG"
    img.filepath_raw = str(path)
    img.save(filepath=str(path))
    bpy.data.images.remove(img)


def planar(key, prefix, size, rule):
    """Orthographic re-skin: bake the scan seen from one side onto a plane -> RGBA + normal."""
    import bmesh
    scan = load_scan(key)
    n_v = len(scan.data.vertices)
    P = np.empty(n_v * 3)
    scan.data.vertices.foreach_get("co", P)
    P = P.reshape(-1, 3)
    c = P.mean(0)
    if rule == "pca":
        w, V = np.linalg.eigh(np.cov((P - c).T))
        n, a = V[:, 0], V[:, 2]                      # thinnest axis = view, longest = image v
        if n[2] < 0:
            n = -n
    else:
        n, a = np.array([0, 0, 1.0]), np.array([0, 1.0, 0])
    b = np.cross(a, n)                               # image u; (u, v, n) right-handed
    pu, pv, pn = (P - c) @ b, (P - c) @ a, (P - c) @ n
    if rule == "pca":                                # stalk (narrow end) -> v = 0
        lo_end = pv < np.percentile(pv, 6)
        hi_end = pv > np.percentile(pv, 94)
        if np.ptp(pu[lo_end]) > np.ptp(pu[hi_end]):
            a, b, pv, pu = -a, -b, -pv, -pu
    side = max(np.ptp(pu), np.ptp(pv)) * 1.04
    cu, cv = 0.5 * (pu.max() + pu.min()), 0.5 * (pv.max() + pv.min())
    h = pn.max() + side * 0.02
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new("UVMap")
    corners = []
    for du, dv in ((-0.5, -0.5), (0.5, -0.5), (0.5, 0.5), (-0.5, 0.5)):
        p = c + b * (cu + du * side) + a * (cv + dv * side) + n * h
        corners.append(bm.verts.new(p.tolist()))
    f = bm.faces.new(corners)
    for loop, uv in zip(f.loops, ((0, 0), (1, 0), (1, 1), (0, 1))):
        loop[uvl].uv = uv
    me = bpy.data.meshes.new("plane")
    bm.to_mesh(me)
    bm.free()
    plane = util.new_object("plane", me)
    me.update()
    if me.polygons[0].normal.dot(Vector(n.tolist())) < 0:
        me.flip_normals()
    util.setup_cycles(32)
    mats = [s_.material for s_ in scan.material_slots if s_.material]
    alpha_src = {}
    for m in mats:
        nt = m.node_tree
        bsdf = next((nd for nd in nt.nodes if nd.type == "BSDF_PRINCIPLED"), None)
        if bsdf is None:   # unlit / emission scans: rebuild a Principled fed by the colour image
            bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
            tex = next(nd for nd in nt.nodes if nd.type == "TEX_IMAGE")
            nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
            nt.links.new(bsdf.outputs[0], bake._output(nt).inputs["Surface"])
        bsdf.name = "BSDF"
        alpha_src[m.name] = bool(bsdf.inputs["Alpha"].links)
    pm = bpy.data.materials.new("plane_mat")
    pm.use_nodes = True
    me.materials.append(pm)
    tgt = pm.node_tree.nodes.new("ShaderNodeTexImage")
    pm.node_tree.nodes.active = tgt
    reach = (h - pn.min()) + side * 0.02

    def run(kind, rewire=None):
        img = bpy.data.images.new(f"{prefix}_{kind}", size, size, float_buffer=True)
        img.colorspace_settings.name = "Non-Color"
        tgt.image = img
        if rewire:
            rewire()
        util.select_only([scan, plane], plane)
        bpy.ops.object.bake(type=kind, use_selected_to_active=True, cage_extrusion=0.0, max_ray_distance=reach,
                            margin=0, normal_space="TANGENT", use_clear=True)
        if rewire:
            bake._restore(mats)
        a_ = bake._pixels(img)
        bpy.data.images.remove(img)
        return a_

    cover = run("EMIT", lambda: _emit_const(mats, (1, 1, 1)))[..., 0]
    col = run("EMIT", lambda: bake._rewire(mats, "Base Color"))[..., :3]
    alpha = cover
    if any(alpha_src.values()):
        alpha = alpha * run("EMIT", lambda: bake._rewire(mats, "Alpha"))[..., 0]
    nrm = run("NORMAL")[..., :3]
    valid = alpha > 0.5
    col = fill_holes(col, valid)
    nrm = fill_holes(nrm * 2 - 1, valid)
    # keep only surface relief: the builders model their own curvature
    nrm = nrm - blur(nrm, max(4, size // 24)) + np.array([0, 0, 1.0], np.float32)
    nrm /= np.maximum(np.linalg.norm(nrm, axis=-1, keepdims=True), 1e-6)
    _save_rgba(f"{prefix}_albedo", np.concatenate([bake._lin2srgb(col), alpha[..., None]], -1),
               util.DERIVED / f"{prefix}_albedo.png")
    bake.save_image(f"{prefix}_normal", nrm * 0.5 + 0.5, util.DERIVED / f"{prefix}_normal.png", "PNG", "Non-Color")
    rows = np.where(valid.any(1))[0]
    cols_ = np.where(valid.any(0))[0]
    info = {"side_m": float(side), "alpha_bbox_uv": [float(cols_.min() / size), float(rows.min() / size),
                                                      float(cols_.max() / size), float(rows.max() / size)]}
    (util.DERIVED / f"{prefix}.json").write_text(json.dumps(info, indent=2) + "\n")
    print(prefix, json.dumps(info))


def daisy_crop(size=1024):
    """Cut the largest daisy head out of ambientCG FlowerSet001 -> RGBA + normal, centred."""
    meta = util.sources_meta()["FlowerSet001"]["files"]

    def load(rel, cs):
        img = bpy.data.images.load(util.cache_file(rel))
        img.colorspace_settings.name = cs
        a_ = bake._pixels(img)
        bpy.data.images.remove(img)
        return a_
    col = load(meta["Color"], "Non-Color")[..., :3]          # keep sRGB-encoded values as stored
    op = load(meta["Opacity"], "Non-Color")[..., 0]
    nrm = load(meta["NormalGL"], "Non-Color")[..., :3]
    mask = op > 0.5

    def runs(v):
        on = np.concatenate([[False], v, [False]])
        d = np.diff(on.astype(int))
        return list(zip(np.where(d == 1)[0], np.where(d == -1)[0]))
    best = None
    for r0, r1 in runs(mask.any(1)):
        for c0, c1 in runs(mask[r0:r1].any(0)):
            area = mask[r0:r1, c0:c1].sum()
            if best is None or area > best[0]:
                best = (area, r0, r1, c0, c1)
    _, r0, r1, c0, c1 = best
    cy, cx = (r0 + r1) / 2, (c0 + c1) / 2
    half = max(r1 - r0, c1 - c0) * 0.53
    ys = np.clip((cy - half + (np.arange(size) + 0.5) * (2 * half / size)).astype(int), 0, op.shape[0] - 1)
    xs = np.clip((cx - half + (np.arange(size) + 0.5) * (2 * half / size)).astype(int), 0, op.shape[1] - 1)
    C, A, N = col[ys][:, xs], op[ys][:, xs], nrm[ys][:, xs]
    C = fill_holes(C, A > 0.5)
    _save_rgba("daisy_head_albedo", np.concatenate([C, A[..., None]], -1), util.DERIVED / "daisy_head_albedo.png")
    bake.save_image("daisy_head_normal", N, util.DERIVED / "daisy_head_normal.png", "PNG", "Non-Color")
    print("daisy_head crop", r0, r1, c0, c1)


def main():
    util.DERIVED.mkdir(parents=True, exist_ok=True)
    only = set(util.script_args())
    for key, (prefix, size, rule) in PLANAR.items():
        if not only or key in only:
            planar(key, prefix, size, rule)
    if not only or "FlowerSet001" in only:
        daisy_crop()
    for key, (prefix, size, passes, rule) in SCANS.items():
        if only and key not in only:
            continue
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
