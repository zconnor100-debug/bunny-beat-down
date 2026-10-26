"""Turn downloaded source models into game-ready environment GLBs (runs inside Blender).

    blender --background --factory-startup --python tools/env/process_models.py -- [ids...]

With no ids every recipe in tools/env/env_recipes.json is built.  For each recipe:

 1. import the cached source (Poly Haven glTF or Sketchfab GLB),
 2. flatten the node hierarchy (bake every parent/instance transform into the
    mesh, drop cameras/lights/empties/armatures),
 3. keep only the wanted sub-objects (regex on object names, or loose parts),
 4. join, optionally rotate, decimate to the triangle budget,
 5. scale to the in-game (critter-world) size, put the ground contact at y = 0
    and centre the footprint on the origin,
 6. rebuild textures with texconv.py (Pillow): JPEG colour/ORM, PNG normals,
    RGBA PNG for cut-out foliage, everything <= the recipe's size cap,
 7. rewire cut-out alpha as an explicit alpha-clip node chain so the glTF
    exporter writes alphaMode MASK (Godot -> alpha scissor),
 8. export assets/env/<id>/<id>.glb (+Y up, transforms applied) and update
    assets/env/manifest.json and tools/_cache/env/_build/<id>.json (stats and a
    human readable "changes" log used for the credits).
"""
from __future__ import annotations

import json
import math
import re
import subprocess
import sys
import time
from pathlib import Path

import bpy
import numpy as np
from mathutils import Euler, Matrix

TOOLS = Path(__file__).resolve().parent
ROOT = TOOLS.parents[1]
CACHE = ROOT / "tools" / "_cache" / "env"
BUILD = CACHE / "_build"
OUT = ROOT / "assets" / "env"
WORK = Path("/tmp/bbd-envwork")
RECIPES = TOOLS / "env_recipes.json"

# Objects that ship inside Sketchfab packs but are never part of an asset:
# reference humans, checker floors, impostor billboards, lower LODs.
DEFAULT_EXCLUDE = [r"(?i)checker", r"(?i)man.?ref", r"(?i)ref_plane", r"(?i)billboard",
                   r"(?i)lod[1-9]"]

MANIFEST_KEYS = ("id", "file", "category", "height_m", "footprint_radius_m", "collision",
                 "collision_radius_m", "scale_range", "density_weight")


# --------------------------------------------------------------------------- utils

def log(*a):
    print("[env]", *a, flush=True)


def source_file(src: str, res: str = "2k") -> tuple[Path, Path, str]:
    kind, ident = src.split(":", 1)
    if kind == "gen":  # procedural generator module in tools/env (e.g. gen:hollow_log)
        return TOOLS / f"{ident}.py", TOOLS, kind
    if kind == "ph":  # several texture resolutions of the same glTF can sit side by side
        d = CACHE / f"ph_{ident}"
        hits = sorted(d.glob(f"*_{res}.gltf")) or sorted(d.glob("*.gltf"))
        return hits[0], d, kind
    if kind == "sf":
        d = CACHE / f"sf_{ident}"
        glb = d / f"{ident}.glb"
        return (glb if glb.exists() else d / "gltf" / "scene.gltf"), d, kind
    raise ValueError(src)


def tri_count(obj) -> int:
    obj.data.calc_loop_triangles()
    return len(obj.data.loop_triangles)


def verts(obj) -> np.ndarray:
    co = np.empty(len(obj.data.vertices) * 3, dtype=np.float64)
    obj.data.vertices.foreach_get("co", co)
    return co.reshape(-1, 3)


def with_objects(objs, active, fn, **kw):
    with bpy.context.temp_override(active_object=active, object=active, selected_objects=objs,
                                   selected_editable_objects=objs):
        return fn(**kw)


# ---------------------------------------------------------------- import & select

def import_flat(path: Path) -> list:
    """Import a glTF and return plain mesh objects with all transforms baked in."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(path))
    dg = bpy.context.evaluated_depsgraph_get()
    flat, names = [], []
    for o in list(bpy.data.objects):
        if o.type != "MESH":
            continue
        me = bpy.data.meshes.new_from_object(o.evaluated_get(dg), preserve_all_data_layers=True, depsgraph=dg)
        me.transform(o.matrix_world)
        if o.matrix_world.determinant() < 0:  # mirrored instance -> fix winding
            me.flip_normals()
        flat.append(bpy.data.objects.new("tmp_flat", me))
        names.append(o.name)
    for o in list(bpy.data.objects):
        if o not in flat:
            bpy.data.objects.remove(o, do_unlink=True)
    for o, name in zip(flat, names):
        o.name = name  # originals are gone, so the source names are free again
        bpy.context.scene.collection.objects.link(o)
    return flat


def select_objects(objs: list, cfg: dict) -> list:
    keep = cfg.get("objects")
    excl = list(cfg.get("exclude", [])) + (DEFAULT_EXCLUDE if cfg.get("default_exclude", True) else [])
    chosen = []
    for o in objs:
        if keep and not any(re.search(p, o.name) for p in keep):
            continue
        if any(re.search(p, o.name) for p in excl):
            continue
        chosen.append(o)
    if not chosen:
        raise RuntimeError("no objects selected; names were: " + ", ".join(o.name for o in objs))
    for o in objs:
        if o not in chosen:
            bpy.data.objects.remove(o, do_unlink=True)
    return chosen


def duplicate_parts(objs: list, specs: list) -> list:
    """Add rotated/offset copies of selected sub-objects (source units, Z up).

    spec = {"pattern": regex, "copies": [{"offset": [x, y, z], "rot_z": deg}, ...]}
    Each copy is rotated about its own footprint centre, then offset.
    """
    out = list(objs)
    for spec in specs:
        for o in [o for o in objs if re.search(spec["pattern"], o.name)]:
            v = verts(o)
            cx, cy = (v[:, 0].min() + v[:, 0].max()) / 2, (v[:, 1].min() + v[:, 1].max()) / 2
            for k, c in enumerate(spec["copies"]):
                dup = o.copy()
                dup.data = o.data.copy()
                dup.name = f"{o.name}_dup{k}"
                bpy.context.scene.collection.objects.link(dup)
                ox, oy, oz = c.get("offset", [0, 0, 0])
                m = (Matrix.Translation((cx + ox, cy + oy, oz))
                     @ Matrix.Rotation(math.radians(c.get("rot_z", 0.0)), 4, "Z")
                     @ Matrix.Translation((-cx, -cy, 0)))
                dup.data.transform(m)
                out.append(dup)
    return out


def join(objs: list):
    if len(objs) == 1:
        return objs[0]
    with_objects(objs, objs[0], bpy.ops.object.join)
    return bpy.context.scene.objects[objs[0].name] if objs[0].name in bpy.context.scene.objects else objs[0]


def pick_loose_parts(obj, picks: list[int]):
    """Split into loose parts, rank by bounding-box volume (largest = 0), keep picks."""
    import bmesh
    me = obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.verts.ensure_lookup_table()
    comp_of, comps = {}, []
    for v in bm.verts:
        if v.index in comp_of:
            continue
        stack, members = [v], []
        comp_of[v.index] = len(comps)
        while stack:
            x = stack.pop()
            members.append(x)
            for e in x.link_edges:
                y = e.other_vert(x)
                if y.index not in comp_of:
                    comp_of[y.index] = len(comps)
                    stack.append(y)
        comps.append(members)

    def vol(members):
        co = np.array([tuple(obj.matrix_world @ m.co) for m in members])
        ext = co.max(0) - co.min(0)
        return float(ext[0] * ext[1] * ext[2] + 1e-12)
    order = sorted(range(len(comps)), key=lambda i: vol(comps[i]), reverse=True)
    keep = {order[i] for i in picks if i < len(order)}
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if comp_of[v.index] not in keep], context="VERTS")
    bm.to_mesh(me)
    bm.free()
    me.update()
    return obj


# ------------------------------------------------------------------- geometry

def _collapse(obj, max_tris: int) -> None:
    """Collapse-decimate towards max_tris (the ratio counts faces, so iterate)."""
    for _ in range(4):
        tris = tri_count(obj)
        if tris <= max_tris:
            return
        mod = obj.modifiers.new("decimate", "DECIMATE")
        mod.decimate_type = "COLLAPSE"
        mod.ratio = max(0.001, max_tris / tris * 0.98)
        mod.use_collapse_triangulate = True
        with_objects([obj], obj, bpy.ops.object.modifier_apply, modifier=mod.name)
        if tri_count(obj) > tris * 0.97:  # stalled (protected borders)
            return


def decimate(obj, max_tris: int) -> tuple[int, int, bool]:
    """Returns (tris before, tris after, welded)."""
    before = tri_count(obj)
    if not max_tris or before <= max_tris:
        return before, before, False
    # glTF stores vertices split along every UV seam.  Decimating that as-is
    # collapses each side of a seam independently and opens cracks (sky shows
    # through as slivers).  Weld coincident vertices first: UVs live on face
    # corners, and the collapse decimator keeps corner UV seams intact.
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    ext = float(np.ptp(verts(obj), axis=0).max())
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6 * max(ext, 1e-3))
    bm.to_mesh(obj.data)
    bm.free()
    _collapse(obj, max_tris)
    for p in obj.data.polygons:
        p.use_smooth = True
    return before, tri_count(obj), True


def mesh_components(me) -> tuple[np.ndarray, np.ndarray]:
    """Connected parts of a mesh, treating coincident vertices (split UV seams) as joined.

    Returns (component id per polygon, component id per vertex).
    """
    nv = len(me.vertices)
    parent = list(range(nv))

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a

    def union(a, b):
        ra, rb = find(a), find(b)
        if ra != rb:
            parent[ra] = rb

    co = np.empty(nv * 3)
    me.vertices.foreach_get("co", co)
    keys = np.round(co.reshape(-1, 3) * 1e4).astype(np.int64)
    first = {}
    for i, k in enumerate(map(tuple, keys)):
        if k in first:
            union(i, first[k])
        else:
            first[k] = i
    for poly in me.polygons:
        vs = poly.vertices
        for v in vs[1:]:
            union(vs[0], v)
    vcomp = np.array([find(i) for i in range(nv)])
    pcomp = np.array([vcomp[p.vertices[0]] for p in me.polygons])
    return pcomp, vcomp


def prune_tree(obj, cfg: dict, notes: list) -> None:
    """Make a giant tree critter-friendly (in-game metres, ground at z = 0).

    * the trunk = parts that start near the ground and run up > 30 % of the tree;
    * any other woody part (bark material) starting below ``branch_min_z`` is removed
      -- stylised root "claws" and low branches;
    * foliage cards (alpha-cut materials) starting below ``foliage_min_z`` are removed,
      as are cards whose nearest woody part was removed (no floating leaves);
    * the tree is re-centred on its trunk axis (so the collision cylinder at the
      origin matches the trunk) and re-grounded so the trunk base sits sink_m deep.
    """
    spec = cfg["prune"]
    me = obj.data
    pcomp, vcomp = mesh_components(me)
    co = verts(obj)
    mats = me.materials
    foliage_mat = {i for i, m in enumerate(mats) if m and alpha_driven(m)}
    pmat = np.empty(len(me.polygons), dtype=np.int32)
    me.polygons.foreach_get("material_index", pmat)

    comps = {}
    for c in np.unique(pcomp):
        vs = np.unique(np.concatenate([np.array(me.polygons[i].vertices) for i in np.nonzero(pcomp == c)[0]]))
        z = co[vs, 2]
        is_fol = np.bincount(np.isin(pmat[pcomp == c], list(foliage_mat)).astype(int), minlength=2).argmax() == 1
        comps[c] = {"verts": vs, "zmin": float(z.min()), "zext": float(z.max() - z.min()), "foliage": bool(is_fol)}
    # trunk(s): tall parts that start in the bottom 10 % of the tree (root claws can
    # hold a trunk a few metres above the lowest point, so this is relative)
    height = float(co[:, 2].max() - co[:, 2].min())
    zfloor = float(co[:, 2].min())
    trunk = {c for c, d in comps.items() if d["zmin"] < zfloor + 0.1 * height and d["zext"] > 0.3 * height}
    if not trunk:
        raise RuntimeError("prune: no trunk found")
    bmin, fmin = float(spec.get("branch_min_z", 6.5)), float(spec.get("foliage_min_z", 7.5))
    removed = {c for c, d in comps.items() if c not in trunk and not d["foliage"] and d["zmin"] < bmin}
    removed |= {c for c, d in comps.items() if d["foliage"] and d["zmin"] < fmin}

    # foliage cards that belonged to a removed branch would float: drop them too
    from mathutils.kdtree import KDTree
    woody = [c for c, d in comps.items() if not d["foliage"] or c in trunk]
    pts = [(int(v), c) for c in woody for v in comps[c]["verts"]]
    kd = KDTree(len(pts))
    for k, (v, _) in enumerate(pts):
        kd.insert(co[v], k)
    kd.balance()
    orphaned = 0
    for c, d in comps.items():
        if d["foliage"] and c not in removed and c not in trunk:
            near = [pts[k][1] for _, k, _ in (kd.find(co[v]) for v in d["verts"][:: max(1, len(d["verts"]) // 6)])]
            if max(set(near), key=near.count) in removed:
                removed.add(c)
                orphaned += 1

    import bmesh
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.faces.ensure_lookup_table()
    dead = [bm.faces[i] for i in np.nonzero(np.isin(pcomp, list(removed)))[0]]
    bmesh.ops.delete(bm, geom=dead, context="FACES")
    bm.to_mesh(me)
    bm.free()
    me.update()
    n_branch = sum(1 for c in removed if not comps[c]["foliage"])
    n_fol = len(removed) - n_branch
    notes.append(f"pruned for critter scale: removed {n_branch} root/low-branch parts below {bmin:g} m and "
                 f"{n_fol} foliage cards below {fmin:g} m (or orphaned)")

    # re-centre on the trunk axis (1-4 m band) and re-ground the trunk base
    co = verts(obj)
    band = co[(co[:, 2] > 1.0) & (co[:, 2] < 4.0)]
    r = np.hypot(band[:, 0] - np.median(band[:, 0]), band[:, 1] - np.median(band[:, 1]))
    core = band[r < np.percentile(r, 60) * 1.6]  # ignore stray twigs in the band
    cx, cy = float(core[:, 0].mean()), float(core[:, 1].mean())
    dz = -float(cfg.get("sink_m", 0.0)) - float(co[:, 2].min())
    me.transform(Matrix.Translation((-cx, -cy, dz)))
    me.update()
    notes.append(f"re-centred on the trunk ({cx:+.2f}, {cy:+.2f} m) and re-grounded ({dz:+.2f} m)")


def setup_cycles(scene, samples: int = 4) -> None:
    scene.render.engine = "CYCLES"
    prefs = bpy.context.preferences.addons["cycles"].preferences
    for backend in ("OPTIX", "CUDA"):
        try:
            prefs.compute_device_type = backend
            prefs.get_devices()
            devs = [d for d in prefs.devices if d.type == backend]
            if devs:
                for d in devs:
                    d.use = True
                scene.cycles.device = "GPU"
                break
        except TypeError:
            continue
    scene.cycles.samples = samples


def bake_normals(high, low, asset_id: str, size: int) -> int:
    """Bake a tangent-space normal map from the full-detail source onto the decimated mesh.

    The source's own normal map was made for the source topology; on a decimated
    mesh its detail no longer lines up with the coarser vertex normals, which
    reads as big flat dark facets in game.  Baking 'selected to active' captures
    both the lost geometry and the original normal-map detail (Cycles shades the
    high-poly with its material normals) against the low-poly's own tangents.
    Returns the number of materials baked.
    """
    scene = bpy.context.scene
    setup_cycles(scene)
    out_dir = WORK / asset_id / "bake"
    out_dir.mkdir(parents=True, exist_ok=True)
    ext = float(np.ptp(verts(low), axis=0).max())
    baked = []
    for i, mat in enumerate(m for m in dict.fromkeys(low.data.materials) if m):
        nt = mat.node_tree
        img = bpy.data.images.new(f"{asset_id}_bakedN{i}", size, size, alpha=False)
        img.colorspace_settings.name = "Non-Color"
        node = nt.nodes.new("ShaderNodeTexImage")
        node.image = img
        for n in nt.nodes:
            n.select = False
        node.select = True
        nt.nodes.active = node
        baked.append((mat, node, img))
    if not baked:
        return 0
    with bpy.context.temp_override(active_object=low, object=low, selected_objects=[high, low],
                                   selected_editable_objects=[high, low]):
        bpy.ops.object.bake(type="NORMAL", normal_space="TANGENT", use_selected_to_active=True,
                            cage_extrusion=0.01 * ext, max_ray_distance=0.04 * ext, margin=16,
                            use_clear=True)
    for mat, node, img in baked:
        path = out_dir / f"{img.name}.png"
        img.filepath_raw = str(path)
        img.file_format = "PNG"
        img.save()
        nt = mat.node_tree
        b = principled(mat)
        nmap = next((n for n in nt.nodes if n.type == "NORMAL_MAP"), None)
        if nmap is None:
            nmap = nt.nodes.new("ShaderNodeNormalMap")
            nt.links.new(nmap.outputs["Normal"], b.inputs["Normal"])
        src = nmap.inputs["Color"].links[0].from_node if nmap.inputs["Color"].is_linked else None
        if src is None or src.type != "TEX_IMAGE":
            src = nt.nodes.new("ShaderNodeTexImage")
            nt.links.new(src.outputs["Color"], nmap.inputs["Color"])
        src.image = bpy.data.images.load(str(path))
        src.image.colorspace_settings.name = "Non-Color"
        nt.nodes.remove(node)
    return len(baked)


def level_ground(obj, cfg: dict) -> None:
    """Rotate a scan so its captured ground patch is horizontal.

    Photo-scans of stumps often include a skirt of soil that was captured on a
    slope; grounded at its lowest point, the rest of the skirt (and the stump)
    then floats.  The lowest vertex in each of 24 angular sectors of the outer
    ring approximates the ground; a least-squares plane through them is rotated
    level.
    """
    me = obj.data
    v = verts(obj)
    c = v[:, :2].mean(0)
    d = v[:, :2] - c
    r = np.hypot(d[:, 0], d[:, 1])
    ang = np.arctan2(d[:, 1], d[:, 0])
    ring = r > 0.55 * r.max()
    pts = []
    for k in range(24):
        lo, hi = -math.pi + k * math.pi / 12, -math.pi + (k + 1) * math.pi / 12
        sel = ring & (ang >= lo) & (ang < hi)
        if sel.any():
            pts.append(v[np.nonzero(sel)[0][np.argmin(v[sel, 2])]])
    pts = np.array(pts)
    A = np.column_stack([pts[:, 0], pts[:, 1], np.ones(len(pts))])
    a, b, _ = np.linalg.lstsq(A, pts[:, 2], rcond=None)[0]
    from mathutils import Vector
    n = Vector((-a, -b, 1.0)).normalized()
    q = n.rotation_difference(Vector((0, 0, 1)))
    me.transform(q.to_matrix().to_4x4())
    me.update()
    cfg.setdefault("_notes", []).append(
        f"levelled the scanned ground patch (tilt {math.degrees(math.acos(min(1.0, n.z))):.1f} deg)")


def thin_ring(obj, k: float) -> None:
    """A ring (a sweatband) made thinner: every vertex drawn in toward the
    ring's inner edge, keeping the hole's size, the height and the texture."""
    me = obj.data
    v = verts(obj)
    cx = float(v[:, 0].min() + v[:, 0].max()) / 2
    cy = float(v[:, 1].min() + v[:, 1].max()) / 2
    r = np.hypot(v[:, 0] - cx, v[:, 1] - cy)
    inner = float(np.percentile(r, 2))
    scale = (inner + (r - inner) * k) / np.maximum(r, 1e-6)
    for vert, s in zip(me.vertices, scale):
        vert.co.x = cx + (vert.co.x - cx) * float(s)
        vert.co.y = cy + (vert.co.y - cy) * float(s)
    me.update()


def place(obj, cfg: dict) -> dict:
    """Rotate, scale to in-game size, ground at z=0, footprint centred. Returns info."""
    me = obj.data
    if cfg.get("rotate_deg"):
        rx, ry, rz = (math.radians(a) for a in cfg["rotate_deg"])
        me.transform(Euler((rx, ry, rz), "XYZ").to_matrix().to_4x4())
    if cfg.get("level"):
        level_ground(obj, cfg)
    v = verts(obj)
    zmin, zmax = float(v[:, 2].min()), float(v[:, 2].max())
    ground_mode = cfg.get("ground", "min")
    if ground_mode == "min":
        ground = zmin
    elif ground_mode == "source":
        ground = 0.0
    else:  # fraction of the source height to bury
        ground = zmin + float(ground_mode) * (zmax - zmin)
    if cfg.get("center", "bbox") == "base":
        band = v[v[:, 2] < ground + 0.04 * (zmax - ground)]
        cx, cy = float(np.median(band[:, 0])), float(np.median(band[:, 1]))
    else:
        cx = float(v[:, 0].min() + v[:, 0].max()) / 2
        cy = float(v[:, 1].min() + v[:, 1].max()) / 2
    src_h = zmax - ground
    scale = float(cfg["scale"]) if "scale" in cfg else float(cfg["height_m"]) / src_h
    me.transform(Matrix.Scale(scale, 4) @ Matrix.Translation((-cx, -cy, -ground)))
    if cfg.get("sink_m"):  # settle the model into the ground by a fixed depth
        me.transform(Matrix.Translation((0, 0, -float(cfg["sink_m"]))))
    me.update()
    return {"source_height_m": round(src_h, 4), "scale_factor": round(scale, 4)}


def clean_mesh(obj, cfg: dict) -> None:
    me = obj.data
    # keep only the first UV map (all our sources use TEXCOORD_0)
    while len(me.uv_layers) > 1:
        me.uv_layers.remove(me.uv_layers[-1])
    # drop colour attributes unless a material reads them
    uses_vcol = any(n.type in ("VERTEX_COLOR", "ATTRIBUTE") for m in me.materials if m and m.node_tree
                    for n in m.node_tree.nodes)
    if not uses_vcol:
        for a in list(me.color_attributes):
            me.color_attributes.remove(a)
    # remove unused material slots
    used = set()
    idx = np.empty(len(me.polygons), dtype=np.int32)
    me.polygons.foreach_get("material_index", idx)
    used = set(int(i) for i in np.unique(idx))
    for i in reversed(range(len(me.materials))):
        if i not in used and len(me.materials) > 1:
            obj.active_material_index = i
            with_objects([obj], obj, bpy.ops.object.material_slot_remove)
    if cfg.get("smooth"):
        for p in me.polygons:
            p.use_smooth = True


# ------------------------------------------------------------------ materials

def principled(mat):
    if not mat or not mat.node_tree:
        return None
    for n in mat.node_tree.nodes:
        if n.type == "BSDF_PRINCIPLED":
            return n
    return None


def image_role(node) -> str:
    """Follow links forward from an image node to classify it."""
    seen, frontier = set(), [node]
    hits = set()
    for _ in range(8):
        nxt = []
        for n in frontier:
            for out in n.outputs:
                for l in out.links:
                    t, s = l.to_node, l.to_socket.name
                    if t.type == "NORMAL_MAP" or t.type == "BUMP":
                        hits.add("normal")
                    elif t.type == "BSDF_PRINCIPLED":
                        if s in ("Base Color", "Emission Color"):
                            hits.add("color")
                        elif s == "Alpha" and out.name == "Alpha":
                            hits.add("alpha")
                        elif s in ("Roughness", "Metallic", "Specular IOR Level"):
                            hits.add("data")
                        elif s == "Normal":
                            hits.add("normal")
                    elif t.type == "GROUP" and "Occlusion" in s:
                        hits.add("data")
                    elif t.name not in seen:
                        seen.add(t.name)
                        nxt.append(t)
        frontier = nxt
    if "normal" in hits:
        return "normal"
    if "color" in hits:
        return "color"
    if "data" in hits:
        return "data"
    return "color" if "alpha" in hits else "unused"


def ensure_principled(mat) -> bool:
    """Rebuild KHR_materials_unlit (and other non-PBR) materials as a lit Principled BSDF.

    Some photo-scans ship unlit materials (light baked into the albedo).  Unlit
    would ignore the game's sun, shadows and fog, so we light them like
    everything else.  Returns True if the material was converted.
    """
    if not mat or not mat.node_tree or principled(mat):
        return False
    nt = mat.node_tree
    out = next((n for n in nt.nodes if n.type == "OUTPUT_MATERIAL"), None) or nt.nodes.new("ShaderNodeOutputMaterial")
    img = next((n for n in nt.nodes if n.type == "TEX_IMAGE" and n.image), None)
    b = nt.nodes.new("ShaderNodeBsdfPrincipled")
    b.inputs["Roughness"].default_value = 0.9
    b.inputs["Metallic"].default_value = 0.0
    if img:
        nt.links.new(img.outputs["Color"], b.inputs["Base Color"])
    for l in list(out.inputs["Surface"].links):
        nt.links.remove(l)
    nt.links.new(b.outputs["BSDF"], out.inputs["Surface"])
    for n in list(nt.nodes):  # drop the unlit helper nodes so the exporter sees plain PBR
        if n not in (out, b, img):
            nt.nodes.remove(n)
    return True


def alpha_driven(mat) -> bool:
    b = principled(mat)
    return bool(b and b.inputs["Alpha"].is_linked)


def alpha_source(mat):
    """(image node, output name) that ultimately drives the BSDF Alpha input, or (None, None)."""
    b = principled(mat)
    if not b or not b.inputs["Alpha"].is_linked:
        return None, None
    frontier = [b.inputs["Alpha"].links[0]]
    for _ in range(6):
        nxt = []
        for link in frontier:
            n = link.from_node
            if n.type == "TEX_IMAGE":
                return n, link.from_socket.name
            for i in n.inputs:
                nxt.extend(i.links)
        frontier = nxt
    return None, None


def wire_alpha_clip(mat, color_node, cutoff: float) -> None:
    """Alpha -> (x < cutoff) -> (1 - x) -> BSDF Alpha  ==  glTF alphaMode MASK."""
    nt, b = mat.node_tree, principled(mat)
    for l in list(b.inputs["Alpha"].links):
        nt.links.remove(l)
    lt = nt.nodes.new("ShaderNodeMath")
    lt.operation = "LESS_THAN"
    lt.inputs[1].default_value = cutoff
    sub = nt.nodes.new("ShaderNodeMath")
    sub.operation = "SUBTRACT"
    sub.inputs[0].default_value = 1.0
    nt.links.new(color_node.outputs["Alpha"], lt.inputs[0])
    nt.links.new(lt.outputs[0], sub.inputs[1])
    nt.links.new(sub.outputs[0], b.inputs["Alpha"])
    # viewport/Cycles preview behaviour (export reads the node chain above)
    if hasattr(mat, "surface_render_method"):
        mat.surface_render_method = "DITHERED"


def make_opaque(mat) -> None:
    b = principled(mat)
    if not b:
        return
    for l in list(b.inputs["Alpha"].links):
        mat.node_tree.links.remove(l)
    b.inputs["Alpha"].default_value = 1.0


def base_color_node(mat):
    b = principled(mat)
    if not b or not b.inputs["Base Color"].is_linked:
        return None
    frontier = [b.inputs["Base Color"].links[0].from_node]
    for _ in range(4):
        nxt = []
        for n in frontier:
            if n.type == "TEX_IMAGE":
                return n
            for i in n.inputs:
                for l in i.links:
                    nxt.append(l.from_node)
        frontier = nxt
    return None


def image_bytes(img) -> tuple[bytes, str]:
    if img.packed_file:
        data = bytes(img.packed_file.data)
    else:
        data = Path(bpy.path.abspath(img.filepath)).read_bytes()
    ext = ".jpg" if data[:3] == b"\xff\xd8\xff" else ".png" if data[:8] == b"\x89PNG\r\n\x1a\n" else ".bin"
    if ext == ".bin" and data[8:12] == b"WEBP":
        ext = ".webp"
    return data, ext


def uv_crops(obj, notes: list) -> dict:
    """Shrink each material's UVs to fill 0..1 and return the UV rect to crop its textures to.

    Poly Haven rock sets share one texture atlas between several rocks; keeping a
    single rock means most of the atlas is wasted, so its texture is cropped to
    the region that rock actually uses (and the UVs stretched to match) before
    downscaling.  Materials whose UVs leave 0..1 (tiling) are left alone.
    """
    me = obj.data
    uv = np.empty(len(me.loops) * 2)
    me.uv_layers[0].data.foreach_get("uv", uv)
    uv = uv.reshape(-1, 2)
    mat_idx = np.empty(len(me.polygons), dtype=np.int32)
    me.polygons.foreach_get("material_index", mat_idx)
    loop_mat = np.repeat(mat_idx, [len(p.loop_indices) for p in me.polygons])
    crops = {}
    for i, mat in enumerate(me.materials):
        sel = loop_mat == i
        if not mat or not sel.any():
            continue
        lo, hi = uv[sel].min(0) - 0.004, uv[sel].max(0) + 0.004
        if lo.min() < -0.01 or hi.max() > 1.01 or np.prod(hi - lo) > 0.8:
            continue
        lo, hi = np.clip(lo, 0, 1), np.clip(hi, 0, 1)
        uv[sel] = (uv[sel] - lo) / (hi - lo)
        crops[mat.name] = [float(lo[0]), float(lo[1]), float(hi[0]), float(hi[1])]
        notes.append(f"texture atlas cropped to the UV region this object uses "
                     f"({(hi - lo)[0] * 100:.0f}% x {(hi - lo)[1] * 100:.0f}%)")
    me.uv_layers[0].data.foreach_set("uv", uv.ravel())
    return crops


def process_materials(obj, cfg: dict, asset_id: str, src_dir: Path, kind: str, notes: list) -> dict:
    work = WORK / asset_id
    (work / "src").mkdir(parents=True, exist_ok=True)
    (work / "tex").mkdir(parents=True, exist_ok=True)
    tex_cap = int(cfg.get("tex", 1024))
    caps = {"color": int(cfg.get("tex_color", tex_cap)), "normal": int(cfg.get("tex_normal", tex_cap)),
            "data": int(cfg.get("tex_data", min(tex_cap, 1024)))}
    alpha_cfg = cfg.get("alpha", "auto")
    cutoff = float(cfg.get("alpha_cutoff", 0.5))

    jobs, plan = [], []  # plan: (node, old image, new path, role, rgba)
    done, planned = {}, {}
    clip_mats = 0
    crops = uv_crops(obj, notes) if cfg.get("uv_crop") else {}
    retex = cfg.get("retexture", {})
    for mat in [m for m in dict.fromkeys(obj.data.materials) if m]:
        if not mat.node_tree:
            continue
        if ensure_principled(mat):
            notes.append(f"unlit material '{mat.name}' rebuilt as lit PBR (roughness 0.9)")
        if cfg.get("dielectric"):
            # scans sometimes carry a bogus metalness channel; wood and bark are not metal
            b = principled(mat)
            for l in list(b.inputs["Metallic"].links):
                mat.node_tree.links.remove(l)
            b.inputs["Metallic"].default_value = 0.0
        cnode = base_color_node(mat)
        want_clip = alpha_cfg == "clip" or (alpha_cfg == "auto" and alpha_driven(mat))
        if want_clip and cnode is None:
            want_clip = False
        # Where does the source's alpha come from?  (a separate mask image is merged
        # into the RGBA albedo below; the base colour's own alpha needs nothing)
        anode, aout = alpha_source(mat)
        separate_mask = None
        if want_clip and anode is not None and anode != cnode and anode.image:
            data, ext = image_bytes(anode.image)
            separate_mask = (work / "src" / f"mask_{len(plan):02d}{ext}", "A" if aout == "Alpha" else "L")
            separate_mask[0].write_bytes(data)
        if want_clip:
            wire_alpha_clip(mat, cnode, cutoff)
            mat.use_backface_culling = False  # foliage cards are seen from both sides
            clip_mats += 1
        else:
            make_opaque(mat)
            # solid meshes render single-sided (sources often flag everything double-
            # sided, which doubles overdraw and shadow cost); thin/open shells opt in
            mat.use_backface_culling = True
        if "double_sided" in cfg:
            mat.use_backface_culling = not cfg["double_sided"]
        b = principled(mat)
        if b and not cfg.get("keep_emission") and b.inputs["Emission Color"].is_linked:
            # some photo-scans ship their albedo again as an unlit emission map,
            # which would make the prop glow in a lit game scene
            for l in list(b.inputs["Emission Color"].links):
                mat.node_tree.links.remove(l)
            b.inputs["Emission Strength"].default_value = 0.0
            notes.append("removed baked emission map")

        for n in mat.node_tree.nodes:
            if n.type != "TEX_IMAGE" or not n.image:
                continue
            img = n.image
            role = image_role(n)
            if role == "unused" or (separate_mask and n == anode):
                continue
            rgba = want_clip and n == cnode
            key = (img.name, rgba)
            if key in planned:  # same image used by several nodes -> encode once
                plan.append((n, img, planned[key], role, rgba))
                continue
            k = len(plan)
            spec = next((v for name, v in retex.items() if mat.name.startswith(name)), None)
            if spec:
                src_path = None
            else:
                data, ext = image_bytes(img)
                src_path = work / "src" / f"{k:02d}{ext}"
                src_path.write_bytes(data)
            if role == "normal":
                dst, mode = work / "tex" / f"{asset_id}_normal{k}.png", "rgb"
            elif role == "data":
                dst, mode = work / "tex" / f"{asset_id}_orm{k}.jpg", "rgb"
            elif rgba:
                dst, mode = work / "tex" / f"{asset_id}_albedo{k}.png", "rgba"
            else:
                dst, mode = work / "tex" / f"{asset_id}_albedo{k}.jpg", "rgb"
            job = {"src": str(src_path), "dst": str(dst), "max": caps["color" if role == "color" else role],
                   "mode": mode, "quality": 88 if role != "data" else 90}
            if mat.name in crops:
                job["crop"] = crops[mat.name]
            if spec:
                # swap in a higher-resolution Poly Haven surface, resampled to the
                # source texture's aspect so the model's UV layout still fits
                tdir = CACHE / f"ph_{spec['ph']}"
                job["size"] = spec.get({"color": "size", "normal": "normal_size"}.get(role, "data_size"),
                                       spec["size"])
                if role == "color":
                    job["src"] = str(tdir / "albedo.jpg")
                elif role == "normal":
                    job["src"] = str(tdir / "normal.png")
                else:
                    job.update({"mode": "orm", "rough_src": str(tdir / "roughness.jpg"),
                                "ao_src": str(tdir / "ao.jpg")})
                    job.pop("src")
            if rgba and separate_mask:
                job["alpha_src"], job["alpha_channel"] = str(separate_mask[0]), separate_mask[1]
            elif rgba and kind == "ph":
                # Poly Haven glTFs ship a JPEG diffuse + a separate alpha mask
                masks = sorted((src_dir / "textures").glob("*_alpha_*"))
                if masks:
                    job["alpha_src"] = str(masks[0])
            jobs.append(job)
            plan.append((n, img, dst, role, rgba))
            planned[key] = dst

    if jobs:
        jf = work / "jobs.json"
        jf.write_text(json.dumps(jobs, indent=1))
        subprocess.run(["python3", "-I", str(TOOLS / "texconv.py"), str(jf)], check=True,
                       stdout=subprocess.DEVNULL)
    for name, spec in retex.items():
        notes.append(f"material '{name}' retextured with Poly Haven '{spec['ph']}' "
                     f"({spec['size'][0]}x{spec['size'][1]}, resampled to the original UV aspect)")
    sizes = {}
    for n, old, dst, role, rgba in plan:
        key = (old.name, rgba)
        if key not in done:
            new = bpy.data.images.load(str(dst))
            new.name = dst.stem
            new.colorspace_settings.name = "Non-Color" if role in ("normal", "data") else "sRGB"
            if rgba:
                new.alpha_mode = "STRAIGHT"
            done[key] = new
            sizes[dst.name] = list(new.size)
        n.image = done[key]
    if clip_mats:
        notes.append("foliage materials converted to alpha-clip (cut-out) with bled RGBA albedo")
    return sizes


# ---------------------------------------------------------------------- stats

def measure(obj, cfg: dict) -> dict:
    v = verts(obj)
    r = np.sqrt(v[:, 0] ** 2 + v[:, 1] ** 2)
    zmin, zmax = float(v[:, 2].min()), float(v[:, 2].max())
    stats = {
        "height_m": round(zmax, 2),
        "sink_m": round(max(0.0, -zmin), 2),
        "footprint_radius_m": round(float(r.max()), 2),
        "aabb_m": [round(float(v[:, 0].max() - v[:, 0].min()), 2), round(zmax - zmin, 2),
                   round(float(v[:, 1].max() - v[:, 1].min()), 2)],  # glTF order x, y(up), z
        "tris": tri_count(obj),
    }
    col = cfg.get("collision", "none")
    if "collision_radius_m" in cfg:
        cr = float(cfg["collision_radius_m"])
    elif col == "cylinder":
        # trunk radius: 85th percentile of radial distance in a band above the root flare
        lo, hi = cfg.get("trunk_band", [0.04, 0.10])
        band = r[(v[:, 2] > lo * zmax) & (v[:, 2] < hi * zmax)]
        cr = float(np.percentile(band, 85)) if len(band) else float(r.max())
    elif col in ("convex", "trimesh"):
        cr = float(np.percentile(r, 95))
    else:
        cr = 0.0
    stats["collision_radius_m"] = round(cr, 2)
    return stats


# --------------------------------------------------------------------- export

def export(obj, asset_id: str, tangents: bool = False) -> Path:
    obj.name = asset_id
    obj.data.name = asset_id
    out_dir = OUT / asset_id
    out_dir.mkdir(parents=True, exist_ok=True)
    out = out_dir / f"{asset_id}.glb"
    for o in bpy.context.scene.objects:
        o.select_set(o == obj)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.gltf(
        filepath=str(out), export_format="GLB", use_selection=True, export_yup=True,
        export_apply=True, export_image_format="AUTO", export_texcoords=True, export_normals=True,
        export_tangents=tangents, export_materials="EXPORT", export_cameras=False, export_lights=False,
        export_animations=False, export_skins=False, export_morph=False, export_extras=False,
        export_vertex_color="MATERIAL")
    return out


def update_manifest(entry: dict, order: list[str]) -> None:
    path = OUT / "manifest.json"
    entries = json.loads(path.read_text()) if path.exists() else []
    by_id = {e["id"]: e for e in entries}
    by_id[entry["id"]] = entry
    rank = {k: i for i, k in enumerate(order)}
    merged = sorted((e for k, e in by_id.items() if k in rank), key=lambda e: rank[e["id"]])
    path.write_text(json.dumps(merged, indent=2) + "\n")


# ----------------------------------------------------------------------- main

def build(cfg: dict, order: list[str]) -> None:
    t0 = time.time()
    asset_id = cfg["id"]
    src_file, src_dir, kind = source_file(cfg["source"], cfg.get("ph_res", "2k"))
    log(f"{asset_id}: {src_file.relative_to(ROOT)}")
    notes = []
    if kind == "gen":
        import importlib
        sys.path.insert(0, str(TOOLS))
        gen = importlib.import_module(src_file.stem)
        bpy.ops.wm.read_factory_settings(use_empty=True)
        objs = [gen.build(cfg, WORK / asset_id / "gen")]
        notes.append("original procedural mesh (tools/env/%s.py) textured with CC0 Poly Haven materials"
                     % src_file.stem)
    else:
        objs = import_flat(src_file)
    objs = select_objects(objs, cfg)
    if cfg.get("objects"):
        notes.append("kept sub-object(s) " + ", ".join(sorted(o.name for o in objs))[:200])
    if cfg.get("duplicate"):
        objs = duplicate_parts(objs, cfg["duplicate"])
        notes.append("arranged extra copies of " + ", ".join(d["pattern"].strip("^$") for d in cfg["duplicate"]))
    obj = join(objs)
    if "loose_parts" in cfg:
        obj = pick_loose_parts(obj, cfg["loose_parts"])
        notes.append(f"separated loose part(s) {cfg['loose_parts']} of the source mesh")
    if cfg.get("thin_ring"):
        thin_ring(obj, float(cfg["thin_ring"]))
        notes.append(f"ring made thinner (x{cfg['thin_ring']} its thickness)")
    placed = place(obj, cfg)
    notes.extend(cfg.pop("_notes", []))
    notes.append(f"rescaled x{placed['scale_factor']:g} to critter-world size, grounded and centred")
    if cfg.get("prune"):
        prune_tree(obj, cfg, notes)
    if cfg.get("rotate_deg"):
        notes.append(f"rotated {cfg['rotate_deg']} deg")
    for mat in [m for m in dict.fromkeys(obj.data.materials) if m]:
        if ensure_principled(mat):
            notes.append(f"unlit material '{mat.name}' rebuilt as lit PBR (roughness 0.9)")
    high = None
    n_src = tri_count(obj)
    # re-bake normals when decimation is heavy (< 60 % of the source triangles kept)
    heavy = bool(cfg.get("max_tris")) and n_src > cfg["max_tris"] and cfg["max_tris"] / n_src < 0.6
    if cfg.get("max_tris") and n_src > cfg["max_tris"] and cfg.get("bake_normals", heavy):
        high = obj.copy()
        high.data = obj.data.copy()
        bpy.context.scene.collection.objects.link(high)
    before, after, welded = decimate(obj, cfg.get("max_tris"))
    if after < before:
        notes.append(f"decimated {before} -> {after} triangles (seams welded first, no cracks)")
    clean_mesh(obj, cfg)
    baked = False
    if high is not None:
        n = bake_normals(high, obj, asset_id, int(cfg.get("tex_normal", cfg.get("tex", 1024))))
        bpy.data.objects.remove(high, do_unlink=True)
        if n:
            baked = True
            notes.append("normal map re-baked from the full-detail source onto the decimated mesh")
    sizes = process_materials(obj, cfg, asset_id, src_dir, kind, notes)
    notes.append("textures re-encoded <= %dpx (JPEG colour/ORM, PNG normals)" % max(
        [max(s) for s in sizes.values()] or [0]))
    stats = measure(obj, cfg)
    out = export(obj, asset_id, tangents=baked)
    stats["file_mb"] = round(out.stat().st_size / 1e6, 2)

    entry = {
        "id": asset_id,
        "file": f"assets/env/{asset_id}/{asset_id}.glb",
        "category": cfg["category"],
        "height_m": stats["height_m"],
        "footprint_radius_m": stats["footprint_radius_m"],
        "collision": cfg.get("collision", "none"),
        "collision_radius_m": stats["collision_radius_m"] if cfg.get("collision", "none") != "none" else 0.0,
        "scale_range": cfg.get("scale_range", [0.85, 1.15]),
        "density_weight": cfg.get("density_weight", 1.0),
        "sink_m": stats["sink_m"],
        "tris": stats["tris"],
    }
    if cfg.get("notes"):
        entry["notes"] = cfg["notes"]
    update_manifest(entry, order)
    BUILD.mkdir(parents=True, exist_ok=True)
    (BUILD / f"{asset_id}.json").write_text(json.dumps(
        {"id": asset_id, "source": cfg["source"], "changes": notes, "stats": stats, "textures": sizes,
         **placed}, indent=1))
    log(f"{asset_id}: {stats['tris']} tris, h={stats['height_m']} m, r={stats['footprint_radius_m']} m, "
        f"{stats['file_mb']} MB, {time.time() - t0:.1f}s")


def main() -> None:
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    recipes = json.loads(RECIPES.read_text())
    # "enabled": false keeps a vetted candidate in the recipe book without shipping it
    assets = [a for a in recipes["assets"] if a.get("enabled", True) or a["id"] in argv]
    order = [a["id"] for a in assets]
    defaults = recipes.get("defaults", {})
    wanted = set(argv)
    failed = []
    for a in assets:
        if wanted and a["id"] not in wanted:
            continue
        cfg = {**defaults, **a}
        try:
            build(cfg, order)
        except Exception as e:  # keep going, report at the end
            import traceback
            traceback.print_exc()
            failed.append((a["id"], str(e)))
    for f in failed:
        log("FAILED", *f)
    if failed:
        sys.exit(1)


if __name__ == "__main__":
    main()
