# Bunny Beat Down — the bosses' models (headless Blender).
#
#   blender -b --factory-startup -P tools/characters/boss_build.py -- <id> grid
#   blender -b --factory-startup -P tools/characters/boss_build.py -- <id> build
#   blender -b --factory-startup -P tools/characters/boss_build.py -- <id> poses
#
# Recipes: tools/characters/bosses.json (one per boss). Raw downloads live in
# tools/_cache/characters/<src>/source.glb (sketchfab_fetch.py fetch <uid> <src>).
#
#   grid   import, face -Y (glTF +Z), stand on z = 0, centre, scale to 1.0 tall,
#          decimate to the recipe's budget, save the result to
#          tools/_cache/characters/<src>/norm.blend and render it front + side
#          (boss_grid.py puts them on a 0.05 grid: grid.png) to read joint positions off
#   build  from norm.blend: a skeleton from the recipe's joints (skinned by bone
#          heat), or the download's own rig cleaned up (recipe "rig": "own");
#          writes assets/bosses/<id>/<id>.glb and <id>.boss.json (bone names
#          per role, hitbox radii, head top, eyes and mouth)
#   poses  renders the built model in a few test poses (poses.png next to the
#          glb's cache), to check the skinning
#
# The bosses are huge (the game scales them to Boss.HEIGHT), so they are
# exported 1 unit tall (to the top of the bounds) and their recipe gives where
# the skull's top is, as a share of that.
import json
import math
import os
import sys
import tempfile

import bpy
import numpy as np
from mathutils import Matrix, Vector

argv = sys.argv[sys.argv.index("--") + 1:]
BID, STAGE = argv[0], argv[1]
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
CFG = json.load(open(os.path.join(HERE, "bosses.json")))[BID]
CACHE = os.path.join(ROOT, "tools", "_cache", "characters", CFG["src"])
NORM = os.path.join(CACHE, "norm.blend")
OUT_DIR = os.path.join(ROOT, "assets", "bosses", BID)
OUT_GLB = os.path.join(OUT_DIR, BID + ".glb")
OUT_JSON = os.path.join(OUT_DIR, BID + ".boss.json")


def log(*a):
    print("BOSS", BID, *a, flush=True)


def objs(kind=None):
    return [o for o in bpy.context.scene.objects if kind is None or o.type == kind]


def select_only(lst, active=None):
    bpy.ops.object.select_all(action="DESELECT")
    for o in lst:
        o.select_set(True)
    bpy.context.view_layer.objects.active = active or lst[0]


def object_mode():
    if bpy.context.object and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")


def tri_count(o):
    return sum(len(p.vertices) - 2 for p in o.data.polygons)


def coords(o):
    n = len(o.data.vertices)
    co = np.empty(n * 3)
    o.data.vertices.foreach_get("co", co)
    co = co.reshape(n, 3)
    M = np.array(o.matrix_world)
    return co @ M[:3, :3].T + M[:3, 3]


def weights_matrix(o, names):
    W = np.zeros((len(o.data.vertices), len(names)))
    idx = {o.vertex_groups[n].index: k for k, n in enumerate(names) if n in o.vertex_groups}
    for v in o.data.vertices:
        for g in v.groups:
            k = idx.get(g.group)
            if k is not None:
                W[v.index, k] = g.weight
    return W


# ============================================================================= grid: normalize
def clean_materials(body):
    """One UV layer, with any texture transform (Mapping nodes, from
    KHR_texture_transform) baked into it, and no emission unless the recipe
    keeps it (photo-scanned models light themselves with their colour map)."""
    mats = [m for m in body.data.materials if m and m.node_tree]
    for m in mats:
        maps = [n for n in m.node_tree.nodes if n.type == "MAPPING"]
        if maps:
            loc = tuple(maps[0].inputs["Location"].default_value)   # (copies: the nodes go below)
            sca = tuple(maps[0].inputs["Scale"].default_value)
            for u in body.data.uv_layers:
                a = np.empty(len(u.data) * 2)
                u.data.foreach_get("uv", a)
                a = a.reshape(-1, 2) * np.array([sca[0], sca[1]]) + np.array([loc[0], loc[1]])
                u.data.foreach_set("uv", a.ravel())
            for mp in maps:
                src = mp.inputs["Vector"].links[0].from_socket if mp.inputs["Vector"].links else None
                for l in list(mp.outputs["Vector"].links):
                    if src:
                        m.node_tree.links.new(src, l.to_socket)
                m.node_tree.nodes.remove(mp)
            log("baked the texture transform into the UVs (scale %.3f %.3f, offset %.3f %.3f)" % (sca[0], sca[1], loc[0], loc[1]))
        if not CFG.get("keep_emission", False):
            bsdf = next((n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
            if bsdf:
                for l in list(bsdf.inputs["Emission Color"].links):
                    log("dropped the emission map", l.from_node.name)
                    m.node_tree.links.remove(l)
                bsdf.inputs["Emission Strength"].default_value = 0.0
        for n in m.node_tree.nodes:
            if n.type == "UVMAP":
                n.uv_map = body.data.uv_layers[0].name
        # (the colour map is the one to show in previews)
        base = next((l.from_node for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED"
                     for l in n.inputs["Base Color"].links if l.from_node.type == "TEX_IMAGE"), None)
        if base:
            m.node_tree.nodes.active = base
    while len(body.data.uv_layers) > 1:
        body.data.uv_layers.remove(body.data.uv_layers[-1])


def normalize():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    src = os.path.join(CACHE, "source.glb")
    if CFG.get("rest_from") == "bind":
        # (its own rig, posed in the file the way it isn't skinned: rest it in
        # the skin's bind pose, as normalize.py does for the critters)
        sys.path.insert(0, HERE)
        import gltf_bind
        fd, src = tempfile.mkstemp(prefix="bbd-bind-", suffix=".glb")
        os.close(fd)
        gltf_bind.rewrite_rest_to_bind(os.path.join(CACHE, "source.glb"), src, CFG.get("anchor"), log=lambda *a: log(*a))
    bpy.ops.import_scene.gltf(filepath=src, guess_original_bind_pose=False)
    if src != os.path.join(CACHE, "source.glb"):
        os.unlink(src)
    for o in objs():
        if o.animation_data:
            o.animation_data.action = None
            for tr in list(o.animation_data.nla_tracks):
                o.animation_data.nla_tracks.remove(tr)
    arms = objs("ARMATURE")
    own = CFG.get("rig") == "own"
    arm = arms[0] if own and arms else None
    drop = CFG.get("drop_meshes", [])
    keep = [o for o in objs("MESH") if not any(d in o.name for d in drop) and o.name != "Icosphere"
            and (not own or any(m.type == "ARMATURE" for m in o.modifiers))]
    for o in ([arm] if arm else []) + keep:
        mw = o.matrix_world.copy()
        o.parent = None
        o.matrix_world = mw
    for o in list(objs()):
        if o is not arm and o not in keep:
            bpy.data.objects.remove(o, do_unlink=True)
    select_only(keep, keep[0])
    bpy.ops.object.make_single_user(object=True, obdata=True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    if len(keep) > 1:
        select_only(keep, max(keep, key=lambda o: len(o.data.vertices)))
        bpy.ops.object.join()
    body = bpy.context.view_layer.objects.active
    body.name = body.data.name = BID + "_body"
    for m in list(body.modifiers):
        body.modifiers.remove(m)
    clean_materials(body)
    # face -Y, feet on the ground, centred, 1 unit tall
    P = coords(body)
    lo, hi = P.min(axis=0), P.max(axis=0)
    yaw = math.radians(CFG.get("yaw_deg", 0.0))
    cx, cy = (lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2
    if CFG.get("centre") == "feet":   # (arms held out in front don't count)
        feet = P[P[:, 2] < lo[2] + 0.06 * (hi[2] - lo[2])]
        cx, cy = (feet[:, 0].min() + feet[:, 0].max()) / 2, (feet[:, 1].min() + feet[:, 1].max()) / 2
    T = (Matrix.Scale(1.0 / float(hi[2] - lo[2]), 4) @ Matrix.Rotation(yaw, 4, "Z")
         @ Matrix.Translation((-cx, -cy, -lo[2])))
    for o in ([arm] if arm else []) + [body]:
        o.matrix_world = T @ o.matrix_world
        select_only([o], o)
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    if arm:
        body.parent = arm
        body.matrix_parent_inverse = Matrix.Identity(4)
        body.modifiers.new("Armature", "ARMATURE").object = arm
    n = tri_count(body)
    budget = CFG.get("max_tris", 60000)
    if n > budget:
        dm = body.modifiers.new("decimate", "DECIMATE")
        dm.ratio = budget / n * 0.98
        dm.use_collapse_triangulate = True
        select_only([body], body)
        bpy.ops.object.modifier_move_to_index(modifier="decimate", index=0)
        bpy.ops.object.modifier_apply(modifier="decimate")
        log("decimated", n, "->", tri_count(body))
    # (loose bits a sculpt leaves behind: specks the skinning can't reach)
    if not own:
        select_only([body], body)
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.mesh.remove_doubles(threshold=0.0004)
        bpy.ops.mesh.delete_loose()
        bpy.ops.object.mode_set(mode="OBJECT")
    P = coords(body)
    log("normalized: tris", tri_count(body), "bounds", P.min(axis=0).round(3).tolist(), P.max(axis=0).round(3).tolist())
    bpy.ops.wm.save_as_mainfile(filepath=NORM)
    return body, arm


# ============================================================================= rendering helpers
def setup_render(res_x, res_y):
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.light = "STUDIO"
    sc.display.shading.color_type = "TEXTURE"
    sc.render.resolution_x, sc.render.resolution_y = res_x, res_y
    sc.render.film_transparent = False
    sc.world = sc.world or bpy.data.worlds.new("w")
    sc.display.shading.background_type = "VIEWPORT"
    sc.display.shading.background_color = (0.93, 0.94, 0.95)


def ortho_camera(loc, rot, scale):
    cam = bpy.data.cameras.new("cam")
    cam.type = "ORTHO"
    cam.ortho_scale = scale
    co = bpy.data.objects.new("cam", cam)
    bpy.context.scene.collection.objects.link(co)
    co.location, co.rotation_euler = loc, rot
    bpy.context.scene.camera = co
    return co


def render_to(path):
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def render_views(name, bones=None):
    """Front + side renders (CACHE/<name>_front.png, _side.png) and the bones
    (CACHE/<name>_bones.json) for tools/characters/boss_grid.py to put on a grid."""
    setup_render(900, 900)
    cam = ortho_camera((0, -5, 0.55), (math.radians(90), 0, 0), 1.2)
    render_to(os.path.join(CACHE, name + "_front.png"))
    cam.location, cam.rotation_euler = (5, 0, 0.55), (math.radians(90), 0, math.radians(90))
    render_to(os.path.join(CACHE, name + "_side.png"))
    with open(os.path.join(CACHE, name + "_bones.json"), "w") as f:
        json.dump(bones or {}, f)
    log("rendered", name)


# ============================================================================= build: the skeleton
ROLES = ["hips", "spine", "chest", "neck", "head", "jaw",
         "l_shoulder", "l_upper_arm", "l_lower_arm", "l_hand", "r_shoulder", "r_upper_arm", "r_lower_arm", "r_hand",
         "l_upper_leg", "l_lower_leg", "l_foot", "r_upper_leg", "r_lower_leg", "r_foot",
         "l_ear", "l_ear_tip", "r_ear", "r_ear_tip", "tail", "key", "l_claw_a", "l_claw_b", "r_claw_a", "r_claw_b"]


def mirror(j):
    """A recipe's joints for the left side, mirrored to make the right (x -> -x)."""
    out = {}
    for name, seg in j.items():
        out[name] = seg
        if name.startswith("l_") and ("r_" + name[2:]) not in j:
            out["r_" + name[2:]] = {"head": [-seg["head"][0]] + seg["head"][1:], "tail": [-seg["tail"][0]] + seg["tail"][1:],
                                   "parent": ("r_" + seg["parent"][2:]) if (seg.get("parent") or "").startswith("l_") else seg.get("parent")}
    return out


def build_auto_rig(body):
    joints = mirror(CFG["joints"])
    arm_data = bpy.data.armatures.new(BID + "_rig")
    arm = bpy.data.objects.new(BID + "_rig", arm_data)
    bpy.context.scene.collection.objects.link(arm)
    select_only([arm], arm)
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm_data.edit_bones
    for name, seg in joints.items():
        b = eb.new(name)
        b.head, b.tail = Vector(seg["head"]), Vector(seg["tail"])
        b.roll = 0.0
    for name, seg in joints.items():
        if seg.get("parent"):
            eb[name].parent = eb[seg["parent"]]
            eb[name].use_connect = False
    for b in eb:   # (deform only the bones that carry skin; the rest are for posing)
        b.use_deform = not joints[b.name].get("no_skin", False)
    bpy.ops.object.mode_set(mode="OBJECT")
    # bone heat skinning. A decimated sculpt is anything but watertight, and
    # bone heat finds no solution on it: weigh a voxel-remeshed copy (closed,
    # clean) instead and copy its weights across, nearest face, interpolated.
    # (Ten times as big while weighing: bone heat is tuned for human-sized meshes.)
    proxy = body.copy()
    proxy.data = body.data.copy()
    proxy.name = "proxy"
    bpy.context.scene.collection.objects.link(proxy)
    for o in (proxy, arm):
        o.matrix_world = Matrix.Scale(10.0, 4) @ o.matrix_world
    rm = proxy.modifiers.new("remesh", "REMESH")
    rm.mode = "VOXEL"
    rm.voxel_size = CFG.get("voxel", 0.004)   # (local units: the object is scaled, not its mesh)
    select_only([proxy], proxy)
    bpy.ops.object.modifier_apply(modifier="remesh")
    if tri_count(proxy) > 120000:
        dm = proxy.modifiers.new("decimate", "DECIMATE")
        dm.ratio = 120000 / tri_count(proxy)
        bpy.ops.object.modifier_apply(modifier="decimate")
    # (whiskers and specks voxelize into little islands no bone can see, and
    # then bone heat fails for the lot: keep the body only)
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(proxy.data)
    bm.verts.ensure_lookup_table()
    seen, islands = set(), []
    for v in bm.verts:
        if v.index in seen:
            continue
        stack, comp = [v], []
        seen.add(v.index)
        while stack:
            x = stack.pop()
            comp.append(x)
            for e in x.link_edges:
                o = e.other_vert(x)
                if o.index not in seen:
                    seen.add(o.index)
                    stack.append(o)
        islands.append(comp)
    biggest = max(len(c) for c in islands)
    doomed = [v for c in islands if len(c) < 0.02 * biggest for v in c]
    bmesh.ops.delete(bm, geom=doomed, context="VERTS")
    bm.to_mesh(proxy.data)
    bm.free()
    log("proxy: dropped %d of %d islands" % (sum(1 for c in islands if len(c) < 0.02 * biggest), len(islands)))
    log("proxy: %d tris" % tri_count(proxy))
    select_only([proxy, arm], arm)
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")
    for o in (proxy, arm):
        mw = o.matrix_world.copy()
        o.parent = None
        o.matrix_world = Matrix.Scale(0.1, 4) @ mw
    for o in (proxy, arm):
        select_only([o], o)
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    for b in arm.data.bones:
        if b.name not in body.vertex_groups:
            body.vertex_groups.new(name=b.name)
    dt = body.modifiers.new("weights", "DATA_TRANSFER")
    dt.object = proxy
    dt.use_vert_data = True
    dt.data_types_verts = {"VGROUP_WEIGHTS"}
    dt.vert_mapping = "POLYINTERP_NEAREST"
    dt.layers_vgroup_select_src = "ALL"
    dt.layers_vgroup_select_dst = "NAME"
    select_only([body], body)
    bpy.ops.object.modifier_apply(modifier="weights")
    bpy.data.objects.remove(proxy, do_unlink=True)
    body.parent = arm
    body.matrix_parent_inverse = Matrix.Identity(4)
    for m in list(body.modifiers):
        body.modifiers.remove(m)
    body.modifiers.new("Armature", "ARMATURE").object = arm
    W = weights_matrix(body, [b.name for b in arm.data.bones])
    unweighted = int((W.sum(axis=1) < 1e-4).sum())
    log("bone heat: %d of %d vertices without weights" % (unweighted, len(body.data.vertices)))
    if unweighted:
        # (bone heat leaves islands it couldn't reach: give those to the nearest bone)
        co = coords(body)
        names = [b.name for b in arm.data.bones if b.use_deform]
        segs = [(np.array(arm.data.bones[n].head_local), np.array(arm.data.bones[n].tail_local)) for n in names]
        miss = np.nonzero(W.sum(axis=1) < 1e-4)[0]
        dist = np.stack([seg_dist(co[miss], a, b) for a, b in segs], axis=1)
        nearest = np.argmin(dist, axis=1)
        for k, i in enumerate(miss):
            body.vertex_groups[names[nearest[k]]].add([int(i)], 1.0, "REPLACE")
    # strict regions: the recipe can pin vertices in a box to one bone (a jaw, a key)
    co = coords(body)
    for name, boxes in CFG.get("pin", {}).items():
        sel = np.zeros(len(co), dtype=bool)
        for bx in boxes:
            lo, hi = np.array(bx[0]), np.array(bx[1])
            sel |= np.all((co >= lo) & (co <= hi), axis=1)
        idx = [int(i) for i in np.nonzero(sel)[0]]
        for vg in body.vertex_groups:
            vg.remove(idx)
        body.vertex_groups[name].add(idx, 1.0, "REPLACE")
        log("pinned %d vertices to %s" % (len(idx), name))
    return arm


def clean_own_rig(body, arm):
    """The download's own rig: drop the bones that deform nothing and aren't in the recipe."""
    keep = set(v for v in CFG["roles"].values() if v)
    W = weights_matrix(body, [b.name for b in arm.data.bones])
    used = {b.name for k, b in enumerate(arm.data.bones) if (W[:, k] > 0).any()}
    select_only([arm], arm)
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm.data.edit_bones
    doomed = {e.name for e in eb if e.name not in used and e.name not in keep}
    for e in eb:
        if e.name in doomed:
            continue
        p = e.parent
        while p is not None and p.name in doomed:
            p = p.parent
        if p is not e.parent:
            e.use_connect = False
            e.parent = p
    for n in doomed:
        eb.remove(eb[n])
    bpy.ops.object.mode_set(mode="OBJECT")
    for vg in list(body.vertex_groups):
        if vg.name not in arm.data.bones:
            body.vertex_groups.remove(vg)
    # Godot-safe names
    for b in arm.data.bones:
        safe = "".join(ch if ch.isalnum() or ch == "_" else "_" for ch in b.name)
        if safe != b.name:
            b.name = safe
    log("own rig: %d bones" % len(arm.data.bones))


def paint_texture(body):
    """Paint onto the base-colour texture by where each texel sits on the
    model (recipe "paint", glTF axes: x its left, y up, z its front): an
    overall tint, matted patches (3D noise), and blood and foam along short
    segments (a mouth, a dribble down the chest, paws), their edges broken up
    by noise. Uses skin_maps.rasterize to find each texel's place."""
    sys.path.insert(0, HERE)
    import skin_maps
    cfg = CFG["paint"]
    mat = body.data.materials[0]
    bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    img = next(l.from_node.image for l in bsdf.inputs["Base Color"].links if l.from_node.type == "TEX_IMAGE")
    w, h = img.size
    px = np.empty(w * h * 4, dtype=np.float32)
    img.pixels.foreach_get(px)
    rgb = px.reshape(h, w, 4)[::-1, :, :3].copy()            # row 0 = top, as glTF's v
    # one corner per loop-triangle corner (UV seams stay seams)
    me = body.data
    me.calc_loop_triangles()
    tris = np.empty(len(me.loop_triangles) * 3, dtype=np.int64)
    me.loop_triangles.foreach_get("loops", tris)
    vidx = np.empty(len(me.loops), dtype=np.int64)
    me.loops.foreach_get("vertex_index", vidx)
    uv = np.empty(len(me.loops) * 2)
    me.uv_layers.active.data.foreach_get("uv", uv)
    uv = uv.reshape(-1, 2)
    co = coords(body)
    P = co[vidx[tris]][:, [0, 2, 1]] * np.array([1.0, 1.0, -1.0])   # Blender -> glTF (x, z, -y)
    UV = uv[tris] * np.array([1.0, -1.0]) + np.array([0.0, 1.0])   # Blender v up -> glTF v down
    prim = {"UV": UV, "P": P, "I": np.arange(len(tris)).reshape(-1, 3), "N": np.zeros_like(P)}
    rast = skin_maps.rasterize([prim], (h, w), pad=6)
    tri, bary = rast["tri"], rast["bary"]
    valid = tri >= 0
    t = np.where(valid, tri, 0)
    pos = (P[prim["I"][t]] * bary[..., None]).sum(axis=2)          # (h, w, 3), glTF
    rng = np.random.default_rng(int(cfg.get("seed", 3)))

    def noise(p, freq):
        n = np.zeros(p.shape[:2])
        for _ in range(4):
            d = rng.normal(size=3)
            d /= np.linalg.norm(d)
            n += np.sin((p @ d) * freq + rng.uniform(0, 6.3))
        return n / 4.0 * 0.5 + 0.5                                    # about 0..1

    def along(p, a, b):
        a, b = np.array(a), np.array(b)
        ab = b - a
        k = np.clip(((p - a) @ ab) / max(float(ab @ ab), 1e-9), 0.0, 1.0)
        return np.linalg.norm(p - (a + k[..., None] * ab), axis=2)

    tint = np.array(cfg.get("tint", [1.0, 1.0, 1.0]))
    rgb[valid] *= tint
    m = cfg.get("matted")
    if m:
        n = noise(pos, m.get("freq", 14.0)) * 0.7 + noise(pos, m.get("freq", 14.0) * 2.7) * 0.3
        cover = np.clip((n - (1.0 - m.get("cover", 0.3))) * 6.0, 0.0, 1.0) * valid
        rgb = rgb * (1.0 - cover[..., None]) + rgb * np.array(m["color"]) * cover[..., None]
    for kind in ("blood", "foam"):
        col = np.array(cfg.get(kind + "_color", [0.4, 0.015, 0.015] if kind == "blood" else [0.93, 0.95, 0.88]))
        for seg in cfg.get(kind, []):
            d = along(pos, seg["from"], seg["to"])
            r = seg["radius"] * (0.6 + 0.8 * noise(pos, seg.get("freq", 60.0)))
            k = np.clip((r - d) / (seg["radius"] * 0.25), 0.0, 1.0) * valid * seg.get("strength", 0.92)
            rgb = rgb * (1.0 - k[..., None]) + col * k[..., None]
    out = np.ones((h, w, 4), dtype=np.float32)
    out[..., :3] = np.clip(rgb[::-1], 0.0, 1.0)
    img.pixels.foreach_set(out.ravel())
    img.update()
    log("painted", img.name, "(%s)" % ", ".join(k for k in ("tint", "matted", "blood", "foam") if cfg.get(k)))


def reencode_textures(body, max_tex=2048):
    """Colour maps as JPEG (normal maps, and anything feeding alpha, stay
    lossless), at most max_tex across: as normalize.py does for the critters."""
    lossless = set()
    for mat in body.data.materials:
        if mat and mat.node_tree:
            for node in mat.node_tree.nodes:
                if node.type == "TEX_IMAGE" and node.image is not None:
                    for out in node.outputs:
                        for link in out.links:
                            if link.to_node.type == "NORMAL_MAP" or link.to_socket.name in ("Normal", "Alpha"):
                                lossless.add(node.image.name)
    tmp = tempfile.mkdtemp(prefix="bbd-boss-tex-")
    for img in list(bpy.data.images):
        if img.size[0] == 0 or img.users == 0 or img.name in lossless:
            continue
        if max(img.size) > max_tex:
            k = max_tex / max(img.size)
            img.scale(max(1, int(img.size[0] * k)), max(1, int(img.size[1] * k)))
        path = os.path.join(tmp, "".join(ch if ch.isalnum() else "_" for ch in img.name) + ".jpg")
        img.file_format = "JPEG"
        img.save(filepath=path, quality=90)
        jpg = bpy.data.images.load(path)
        jpg.pack()
        jpg.colorspace_settings.name = img.colorspace_settings.name
        name = img.name
        img.user_remap(jpg)
        bpy.data.images.remove(img)
        jpg.name = name
        jpg.filepath_raw = ""


def seg_dist(P, a, b):
    ab = b - a
    t = np.clip(((P - a) @ ab) / max(float(ab @ ab), 1e-12), 0.0, 1.0)
    return np.linalg.norm(P - (a + t[:, None] * ab), axis=1)


def build():
    bpy.ops.wm.open_mainfile(filepath=NORM)
    body = next(o for o in objs("MESH"))
    arm = next(iter(objs("ARMATURE")), None)
    if CFG.get("rig") == "own":
        clean_own_rig(body, arm)
        roles = {r: CFG["roles"].get(r) for r in ROLES if CFG["roles"].get(r)}
        roles = {r: "".join(ch if ch.isalnum() or ch == "_" else "_" for ch in n) for r, n in roles.items()}
    else:
        arm = build_auto_rig(body)
        roles = {r: r for r in ROLES if r in arm.data.bones}
    select_only([body], body)
    bpy.ops.object.vertex_group_limit_total(group_select_mode="ALL", limit=4)
    bpy.ops.object.vertex_group_normalize_all(group_select_mode="ALL", lock_active=False)
    # hitbox radius per role: median distance from the bone to the vertices it owns
    names = [b.name for b in arm.data.bones]
    co, W = coords(body), weights_matrix(body, names)
    col = {n: i for i, n in enumerate(names)}
    dominant = np.argmax(W, axis=1)
    radii = {}
    for r, bn in roles.items():
        if bn not in col:
            continue
        w = W[:, col[bn]]
        sel = (w > 0.5) | ((dominant == col[bn]) & (w >= 0.3))
        if sel.sum() < 4:
            continue
        b = arm.data.bones[bn]
        d = seg_dist(co[sel], np.array(b.head_local), np.array(b.tail_local))
        radii[r] = round(float(np.percentile(d, 70)), 4)
    os.makedirs(OUT_DIR, exist_ok=True)
    if CFG.get("paint"):
        paint_texture(body)
    reencode_textures(body)
    arm.name = arm.data.name = BID + "_rig"
    body.name = body.data.name = BID + "_body"
    for a in list(bpy.data.actions):
        bpy.data.actions.remove(a)
    select_only([arm, body], arm)
    props = bpy.ops.export_scene.gltf.get_rna_type().properties.keys()
    kw = dict(filepath=OUT_GLB, export_format="GLB", use_selection=True, export_skins=True,
              export_animations=False, export_yup=True, export_apply=False, export_image_format="AUTO",
              export_cameras=False, export_lights=False)
    for k, v in (("export_image_quality", 88), ("export_jpeg_quality", 88), ("export_def_bones", False)):
        if k in props:
            kw[k] = v
    bpy.ops.export_scene.gltf(**kw)

    def gl(v):   # Blender (x, y = back, z = up) -> glTF/Godot (x, y = up, z = forward)
        return [round(v[0], 4), round(v[2], 4), round(-v[1], 4)]
    info = {
        "id": BID,
        "display_name": CFG["display_name"],
        "head_top": CFG["head_top"],
        "bones": roles,
        "radii": radii,
        "tails": {r: gl(arm.data.bones[bn].tail_local) for r, bn in roles.items() if bn in arm.data.bones},
        "eyes": [gl(e) for e in CFG.get("eyes", [])],
        "eye_r": CFG.get("eye_r", 0.02),
        "mouth": gl(CFG["mouth"]) if CFG.get("mouth") else None,
        "tris": tri_count(body),
        "notes": "Facing +Z (glTF/Godot), +Y up, 1 unit tall to the top of its bounds (the game scales it); "
                 "feet on y = 0, centred. eyes/mouth are in those units, before any posing.",
    }
    with open(OUT_JSON, "w") as f:
        json.dump(info, f, indent=2)
        f.write("\n")
    log("exported", OUT_GLB, "%.2f MB" % (os.path.getsize(OUT_GLB) / 1e6), "tris", info["tris"], "bones", len(names))
    bones = {b.name: (list(arm.data.bones[b.name].head_local), list(arm.data.bones[b.name].tail_local)) for b in arm.data.bones}
    render_views("rig", bones)


# ============================================================================= poses: check the skinning
def poses():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=OUT_GLB)
    arm = objs("ARMATURE")[0]
    info = json.load(open(OUT_JSON))
    roles = info["bones"]
    tests = CFG.get("test_poses", [])
    import glob
    for old in glob.glob(os.path.join(CACHE, "pose_*.png")):
        os.remove(old)
    setup_render(600, 600)
    ortho_camera((3.2, -3.2, 2.15), (math.radians(70), 0, math.radians(45)), 1.3)   # (aimed at the middle of it)
    for k, pose in enumerate([{}] + tests):
        for pb in arm.pose.bones:
            pb.rotation_mode = "XYZ"
            pb.rotation_euler = (0, 0, 0)
        for role, eul in pose.items():
            if role in roles and roles[role] in arm.pose.bones:
                arm.pose.bones[roles[role]].rotation_euler = [math.radians(a) for a in eul]
        bpy.context.view_layer.update()
        render_to(os.path.join(CACHE, "pose_%d.png" % k))
    log("rendered %d poses" % (len(tests) + 1))


if STAGE == "grid":
    normalize()
    render_views("grid")
elif STAGE == "build":
    build()
elif STAGE == "poses":
    poses()
else:
    raise SystemExit("stage: grid | build | poses")
