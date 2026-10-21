"""Atlas unwrap -> Cycles channel bakes -> single PBR material -> glTF export.

The pipeline for one asset:

1. every part gets an ``atlas`` UV map (lathes/sweeps reuse their clean
   cylindrical ``src`` UVs, everything else is smart-projected); all islands are
   area-normalised and packed together into one 0..1 square.
2. Base colour, roughness and metallic are baked by temporarily routing each
   Principled input into an Emission shader (works for metals, unlike the
   DIFFUSE colour pass); tangent-space normals and ambient occlusion are baked
   natively. The GPU makes this a few seconds per asset.
3. numpy composes albedo (with a little AO folded in), an ORM map
   (R=occlusion, G=roughness, B=metallic — glTF layout) and the normal map.
4. All baked parts get one material; parts are joined per output node; named
   empties are added for game-side markers and the scene is written as .glb.
"""
from __future__ import annotations

import json
import math
from pathlib import Path

import bpy
import numpy as np
from mathutils import Matrix, Vector

from .util import BUILD, gltf_vec, select_only, setup_cycles, tri_count, world_bounds


# --------------------------------------------------------------------------- UVs

def _edit(objs, fn):
    select_only(objs, objs[0])
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    fn()
    bpy.ops.object.mode_set(mode="OBJECT")


def seed_atlas_uv(objs, angle=60.0):
    """Create the `atlas` UV map: copy clean builder UVs (bbd_uv='src') or smart-project."""
    sc = bpy.context.scene
    sc.tool_settings.use_uv_select_sync = True
    smart = []
    for o in objs:
        uvs = o.data.uv_layers
        if "src" not in uvs:
            uvs.new(name="src")
        at = uvs.get("atlas") or uvs.new(name="atlas")
        if o.get("bbd_uv", "smart") == "src":
            src = uvs["src"]
            buf = np.empty(len(src.data) * 2, np.float32)
            src.data.foreach_get("uv", buf)
            at.data.foreach_set("uv", buf)
        else:
            smart.append(o)
        uvs.active = at
    if smart:
        _edit(smart, lambda: bpy.ops.uv.smart_project(angle_limit=math.radians(angle), island_margin=0.0,
                                                       area_weight=0.0, correct_aspect=True, scale_to_bounds=False))
    # one texel density across all parts, then optional per-part emphasis
    # (bbd_texel = linear multiplier, e.g. the balloon basket vs. its envelope)
    _edit(objs, lambda: bpy.ops.uv.average_islands_scale())
    for o in objs:
        k = float(o.get("bbd_texel", 1.0))
        if k != 1.0:
            at = o.data.uv_layers["atlas"]
            buf = np.empty(len(at.data) * 2, np.float32)
            at.data.foreach_get("uv", buf)
            at.data.foreach_set("uv", buf * k)


def pack_atlas_uv(objs, margin=0.004):
    """Pack all (already density-normalised) islands into one 0..1 square."""
    for o in objs:
        o.data.uv_layers.active = o.data.uv_layers["atlas"]

    def pack():
        bpy.ops.uv.pack_islands(rotate=True, rotate_method="ANY", scale=True, margin_method="SCALED",
                                margin=margin, shape_method="CONCAVE")
    _edit(objs, pack)


# --------------------------------------------------------------------------- bakes

def _output(nt):
    for n in nt.nodes:
        if n.type == "OUTPUT_MATERIAL" and n.is_active_output:
            return n
    return [n for n in nt.nodes if n.type == "OUTPUT_MATERIAL"][0]


def _rewire(mats, socket_name):
    for m in mats:
        nt = m.node_tree
        bsdf = nt.nodes["BSDF"]
        em = nt.nodes.new("ShaderNodeEmission")
        em.name = "BAKE_EMIT"
        sock = bsdf.inputs[socket_name]
        if sock.links:
            nt.links.new(sock.links[0].from_socket, em.inputs["Color"])
        else:
            v = sock.default_value
            em.inputs["Color"].default_value = (v[0], v[1], v[2], 1) if hasattr(v, "__len__") else (v, v, v, 1)
        nt.links.new(em.outputs[0], _output(nt).inputs["Surface"])


def _restore(mats):
    for m in mats:
        nt = m.node_tree
        nt.nodes.remove(nt.nodes["BAKE_EMIT"])
        nt.links.new(nt.nodes["BSDF"].outputs[0], _output(nt).inputs["Surface"])


def _pixels(img):
    w, h = img.size
    a = np.empty(w * h * 4, np.float32)
    img.pixels.foreach_get(a)
    return a.reshape(h, w, 4)


def _lin2srgb(x):
    x = np.clip(x, 0.0, 1.0)
    return np.where(x <= 0.0031308, x * 12.92, 1.055 * np.power(x, 1 / 2.4) - 0.055)


def save_image(name, rgb, path, fmt, colorspace="sRGB", quality=92):
    h, w = rgb.shape[:2]
    img = bpy.data.images.new(name, w, h, alpha=False)
    img.colorspace_settings.name = colorspace
    rgba = np.ones((h, w, 4), np.float32)
    rgba[..., :3] = np.clip(rgb, 0, 1)
    img.pixels.foreach_set(rgba.ravel())
    img.file_format = fmt
    img.filepath_raw = str(path)
    img.save(filepath=str(path), quality=quality)
    bpy.data.images.remove(img)
    return str(path)


def bake_maps(objs, key, size=1024, samples=16, ao_samples=128, ao_distance=0.08, ao_in_albedo=0.45,
              hide=()):
    """Bake the asset's source materials into albedo / ORM / normal images."""
    setup_cycles(samples)
    sc = bpy.context.scene
    if sc.world is None:
        sc.world = bpy.data.worlds.new("bake_world")
    sc.world.light_settings.distance = ao_distance
    sc.render.bake.margin = 8
    sc.render.bake.margin_type = "EXTEND"
    for o in hide:
        o.hide_render = True

    mats = []
    for o in objs:
        for s in o.material_slots:
            if s.material and s.material not in mats:
                mats.append(s.material)
    imgs = {}
    for p in ("col", "rough", "metal", "nrm", "ao"):
        img = bpy.data.images.new(f"{key}_{p}", size, size, alpha=False, float_buffer=True)
        img.colorspace_settings.name = "Non-Color"
        imgs[p] = img
    targets = []
    for m in mats:
        n = m.node_tree.nodes.new("ShaderNodeTexImage")
        n.name = "BAKE_TARGET"
        targets.append((m, n))

    import time
    timings = {}

    def run(kind, img, label, **kw):
        t0 = time.time()
        for m, n in targets:
            n.image = img
            m.node_tree.nodes.active = n
        select_only(objs, objs[0])
        bpy.ops.object.bake(type=kind, margin=8, margin_type="EXTEND", use_clear=True, **kw)
        timings[label] = round(time.time() - t0, 1)

    # colour carries the noisy Bevel/AO-node wear masks -> full samples; the
    # scalar channels only need anti-aliasing
    for chan, sock, spp in (("col", "Base Color", samples), ("rough", "Roughness", max(4, samples // 2)),
                            ("metal", "Metallic", max(4, samples // 2))):
        _rewire(mats, sock)
        sc.cycles.samples = spp
        run("EMIT", imgs[chan], chan)
        _restore(mats)
    sc.cycles.samples = samples
    run("NORMAL", imgs["nrm"], "nrm", normal_space="TANGENT")
    sc.cycles.samples = ao_samples
    run("AO", imgs["ao"], "ao")
    print("bake timings (s):", timings)
    for m, n in targets:
        m.node_tree.nodes.remove(n)
    for o in hide:
        o.hide_render = False

    col = _pixels(imgs["col"])[..., :3]
    rough = _pixels(imgs["rough"])[..., 0]
    metal = _pixels(imgs["metal"])[..., 0]
    nrm = _pixels(imgs["nrm"])[..., :3]
    ao = np.clip(_pixels(imgs["ao"])[..., 0], 0.0, 1.0)
    albedo = col * (1.0 - ao_in_albedo * (1.0 - ao))[..., None]
    out_dir = BUILD / key
    out_dir.mkdir(parents=True, exist_ok=True)
    # images are bottom-up in Blender; files are written the same way bpy reads them
    paths = {
        "albedo": save_image(f"{key}_albedo", _lin2srgb(albedo), out_dir / f"{key}_albedo.jpg", "JPEG"),
        "orm": save_image(f"{key}_orm", np.stack([ao, np.clip(rough, 0.04, 1), np.clip(metal, 0, 1)], -1),
                          out_dir / f"{key}_orm.jpg", "JPEG", "Non-Color"),
        "normal": save_image(f"{key}_normal", nrm, out_dir / f"{key}_normal.png", "PNG", "Non-Color"),
    }
    for img in imgs.values():
        bpy.data.images.remove(img)
    return paths


# --------------------------------------------------------------------------- final material

def _gltf_settings_group():
    name = "glTF Material Output"
    ng = bpy.data.node_groups.get(name)
    if ng is None:
        ng = bpy.data.node_groups.new(name, "ShaderNodeTree")
        ng.interface.new_socket("Occlusion", in_out="INPUT", socket_type="NodeSocketFloat")
    return ng


def final_material(key, paths):
    mat = bpy.data.materials.new(f"{key}_mat")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    uv = nt.nodes.new("ShaderNodeUVMap")
    uv.uv_map = "atlas"

    def tex(path, cs):
        n = nt.nodes.new("ShaderNodeTexImage")
        n.image = bpy.data.images.load(path, check_existing=False)
        n.image.colorspace_settings.name = cs
        nt.links.new(uv.outputs["UV"], n.inputs["Vector"])
        return n

    alb = tex(paths["albedo"], "sRGB")
    orm = tex(paths["orm"], "Non-Color")
    nrm = tex(paths["normal"], "Non-Color")
    nt.links.new(alb.outputs["Color"], bsdf.inputs["Base Color"])
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    nt.links.new(orm.outputs["Color"], sep.inputs["Color"])
    nt.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
    nt.links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])
    grp = nt.nodes.new("ShaderNodeGroup")
    grp.node_tree = _gltf_settings_group()
    nt.links.new(sep.outputs["Red"], grp.inputs["Occlusion"])
    nm = nt.nodes.new("ShaderNodeNormalMap")
    nm.uv_map = "atlas"
    nt.links.new(nrm.outputs["Color"], nm.inputs["Color"])
    nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    bsdf.inputs["Specular IOR Level"].default_value = 0.5
    # single-sided in glTF (thin parts like leaves are modelled two-sided)
    mat.use_backface_culling = True
    return mat


# --------------------------------------------------------------------------- assemble + export

def _join(objs, name):
    from .util import join
    o = join(objs, name)
    o.name = name
    o.data.name = name
    return o


def assemble_and_export(key, spec, out_path, size=1024, ao_distance=0.08, samples=16):
    """spec: dict produced by an asset builder.

    spec["objects"]   all mesh parts; each may carry custom props
                      bbd_node (output node name, default = key), bbd_bake (False to keep own material),
                      bbd_uv ('src' to reuse the builder's UVs in the atlas)
    spec["markers"]   {name: (x, y, z)} Blender coords -> exported as empties
    spec["pivots"]    {node: (x, y, z)} origin for separately exported nodes (Lid, Chute, ...)
    """
    objs = [o for o in spec["objects"] if o and o.type == "MESH"]
    for o in objs:
        if not o.data.materials:
            raise RuntimeError(f"{o.name} has no material")
    baked = [o for o in objs if o.get("bbd_bake", True)]
    unbaked = [o for o in objs if not o.get("bbd_bake", True)]

    # the unbaked parts keep their own UVs as the only UV map
    for o in unbaked:
        uvs = o.data.uv_layers
        at = uvs.get("atlas") or uvs.new(name="atlas")
        buf = np.empty(len(uvs["src"].data) * 2, np.float32)
        uvs["src"].data.foreach_get("uv", buf)
        at.data.foreach_set("uv", buf)

    sources = set()
    for o in objs:
        for s in o.material_slots:
            if s.material and s.material.get("bbd_sources"):
                sources.update(x for x in s.material["bbd_sources"].split(",") if x)

    # Seed atlas UVs per part, then join the baked parts per output node: Cycles
    # bakes object-by-object with a fixed overhead each, so ~100 tiny parts would
    # cost minutes while a handful of joined meshes bake in seconds. (Object-space
    # texture coordinates therefore become node space for all bake materials.)
    seed_atlas_uv(baked)
    for o in objs:
        o.data.transform(o.matrix_world)
        o.matrix_world = Matrix.Identity(4)
    groups, extra = {}, {}
    for o in baked:
        groups.setdefault(o.get("bbd_node", key), []).append(o)
    for o in unbaked:
        extra.setdefault(o.get("bbd_node", key), []).append(o)
    nodes = {name: _join(p, name) for name, p in groups.items()}
    pack_atlas_uv(list(nodes.values()))
    paths = bake_maps(list(nodes.values()), key, size=size, ao_distance=ao_distance, samples=samples,
                      hide=unbaked)
    fmat = final_material(key, paths)
    for node in nodes.values():
        node.data.materials.clear()
        node.data.materials.append(fmat)
        for p in node.data.polygons:
            p.material_index = 0
    for name, p in extra.items():
        nodes[name] = _join(([nodes[name]] if name in nodes else []) + p, name)
    nodes = list(nodes.values())
    for o in nodes:
        for uvl in list(o.data.uv_layers):
            if uvl.name != "atlas":
                o.data.uv_layers.remove(uvl)
    pivots = spec.get("pivots", {})
    for node in nodes:
        pv = Vector(pivots.get(node.name, (0, 0, 0)))
        if pv.length:
            node.data.transform(Matrix.Translation(-pv))
            node.location = pv

    empties = []
    for mname, pos in spec.get("markers", {}).items():
        e = bpy.data.objects.new(mname, None)
        e.empty_display_type = "PLAIN_AXES"
        e.empty_display_size = 0.02
        e.location = Vector(pos)
        bpy.context.scene.collection.objects.link(e)
        empties.append(e)

    select_only(nodes + empties, nodes[0])
    out_path = Path(out_path)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(out_path), export_format="GLB", use_selection=True, export_yup=True,
        export_apply=True, export_texcoords=True, export_normals=True, export_tangents=False,
        export_materials="EXPORT", export_image_format="AUTO", export_jpeg_quality=90,
        export_cameras=False, export_lights=False, export_animations=False, export_extras=False,
        export_vertex_color="NONE")

    lo, hi = world_bounds(nodes)
    glo, ghi = gltf_vec(lo), gltf_vec(hi)
    aabb_min = [min(glo[i], ghi[i]) for i in range(3)]
    aabb_max = [max(glo[i], ghi[i]) for i in range(3)]
    report = {
        "id": key,
        "file": str(out_path),
        "bytes": out_path.stat().st_size,
        "tris": {n.name: tri_count(n) for n in nodes},
        "tris_total": sum(tri_count(n) for n in nodes),
        "aabb_min": aabb_min,
        "aabb_max": aabb_max,
        "size_m": [round(aabb_max[i] - aabb_min[i], 3) for i in range(3)],
        "markers": {e.name: gltf_vec(e.location) for e in empties},
        "nodes": {n.name: gltf_vec(n.location) for n in nodes},
        "texture_px": size,
        "sources": sorted(sources),
    }
    report.update(spec.get("report", {}))
    (BUILD / f"{key}.json").write_text(json.dumps(report, indent=2) + "\n")
    return report
