# Bunny Beat Down — normalize a downloaded Sketchfab character to the game's
# character contract (docs/ASSET_PIPELINE.md, "Characters").
#
#   blender --background --python tools/characters/normalize.py -- <id> [--src file.glb] [--out-dir dir]
#
# Reads the recipe for <id> from tools/characters/roster.json and the raw
# download from tools/_cache/characters/<id>/source.glb (see sketchfab_fetch.py),
# and writes assets/characters/<id>/<id>.glb + <id>.rig.json.
#
# Pipeline
#   1. import (optionally with the rest pose rebuilt from the skin's inverse
#      bind matrices, see gltf_bind.py)
#   2. pick the armature and the meshes it deforms
#   3. record the kept animation clips as world-space bone matrices (while the
#      file's node hierarchy is still intact)
#   2b. skin rigid parts (eyes) to a bone; drop props / Sketchfab helper
#      nodes; join into one mesh
#   4. rig surgery: re-parent, split bones, prune non-deforming control bones,
#      Godot-safe bone names
#   5. orient (faces -Y in Blender = +Z in glTF/Godot), scale so the top of the
#      skull sits at head_top, soles on the ground, centred between the feet;
#      apply all transforms
#   6. decimate to <= 20k triangles if needed, textures <= 2048 px,
#      JPEG for colour / PNG for normal maps and alpha
#   7. re-bake the recorded clips onto the cleaned rig
#   8. measure ragdoll radii, eye height, rest pose; export GLB + <id>.rig.json
import json
import math
import os
import re
import shutil
import sys
import tempfile

import bpy
import numpy as np
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
sys.dont_write_bytecode = True
import gltf_bind  # noqa: E402

MAX_TRIS = 20000
MAX_TEX = 2048
ROLE_ORDER = ["hips", "spine", "chest", "neck", "head", "jaw",
              "l_upper_arm", "l_lower_arm", "l_hand", "r_upper_arm", "r_lower_arm", "r_hand",
              "l_upper_leg", "l_lower_leg", "l_foot", "r_upper_leg", "r_lower_leg", "r_foot"]


def log(*a):
    print("NORMALIZE", *a)


# ----------------------------------------------------------------------------- args
argv = sys.argv[sys.argv.index("--") + 1:]
CID = argv[0]


def opt(name, default=None):
    return argv[argv.index(name) + 1] if name in argv else default


with open(os.path.join(HERE, "roster.json")) as f:
    CFG = json.load(f)[CID]
SRC = opt("--src", os.path.join(ROOT, "tools", "_cache", "characters", CID, "source.glb"))
OUT_DIR = opt("--out-dir", os.path.join(ROOT, "assets", "characters", CID))
os.makedirs(OUT_DIR, exist_ok=True)
OUT_GLB = os.path.join(OUT_DIR, CID + ".glb")
OUT_RIG = os.path.join(OUT_DIR, CID + ".rig.json")


# ----------------------------------------------------------------------------- helpers
def objs(kind=None):
    return [o for o in bpy.context.scene.objects if kind is None or o.type == kind]


def select_only(lst, active=None):
    bpy.ops.object.select_all(action="DESELECT")
    for o in lst:
        o.select_set(True)
    bpy.context.view_layer.objects.active = active or (lst[0] if lst else None)


def deformed_by(o, arm):
    return o.type == "MESH" and any(m.type == "ARMATURE" and m.object == arm for m in o.modifiers)


def mesh_world_coords(o):
    co = np.empty(len(o.data.vertices) * 3)
    o.data.vertices.foreach_get("co", co)
    co = co.reshape(-1, 3)
    M = np.array(o.matrix_world)
    return co @ M[:3, :3].T + M[:3, 3]


def tri_count(o):
    o.data.calc_loop_triangles()
    return len(o.data.loop_triangles)


def weights_matrix(o, names):
    """(n_verts, len(names)) array of vertex weights for the given groups."""
    idx = {g.name: g.index for g in o.vertex_groups}
    cols = {idx[n]: k for k, n in enumerate(names) if n in idx}
    W = np.zeros((len(o.data.vertices), len(names)))
    for v in o.data.vertices:
        for g in v.groups:
            k = cols.get(g.group)
            if k is not None:
                W[v.index, k] = g.weight
    return W


def sanitize(name):
    """Drop the _NN suffix Sketchfab appends to node names; Godot-safe characters only."""
    n = re.sub(r"_\d+$", "", name)
    n = re.sub(r"[^A-Za-z0-9_]", "_", n)
    n = re.sub(r"_+", "_", n).strip("_")
    return n or "bone"


def edit_mode(arm):
    select_only([arm], arm)
    bpy.ops.object.mode_set(mode="EDIT")
    return arm.data.edit_bones


def object_mode():
    if bpy.context.object and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")


def bbox_centre(o):
    P = mesh_world_coords(o)
    return Vector(((P.min(axis=0) + P.max(axis=0)) / 2).tolist())


# ============================================================================= 1. import
bpy.ops.wm.read_factory_settings(use_empty=True)
src = SRC
if CFG.get("rest_from", "node") == "bind":
    fd, src = tempfile.mkstemp(prefix="bbd-bind-", suffix=".glb")
    os.close(fd)
    gltf_bind.rewrite_rest_to_bind(SRC, src, CFG.get("anchor"), log=lambda *a: log(*a))
bpy.ops.import_scene.gltf(filepath=src, guess_original_bind_pose=False)
if src != SRC:
    os.unlink(src)
scene = bpy.context.scene
log("imported", SRC, "rest from", CFG.get("rest_from", "node"))

# ============================================================================= 2. pick the rig
arms = objs("ARMATURE")
if not arms:
    raise SystemExit("no armature in " + SRC)
arm = max(arms, key=lambda a: sum(len(o.data.vertices) for o in objs("MESH") if deformed_by(o, a)))
rigid = CFG.get("rigid_bind", {})
drop = CFG.get("drop_meshes", [])
keep = [o for o in objs("MESH")
        if not any(d in o.name for d in drop) and (deformed_by(o, arm) or o.name in rigid)]

# ============================================================================= 3. record clips
# The importer assigns the first clip and stashes the others in NLA tracks.
# A clip can animate several objects (the armature AND its parent empties:
# one action slot per object), so every object gets its own slot bound while
# we sample, with the node hierarchy still intact; the result is the
# world-space matrix of every bone at every frame.
def clear_animation():
    for o in objs():
        if o.animation_data:
            o.animation_data.action = None
            for tr in list(o.animation_data.nla_tracks):
                o.animation_data.nla_tracks.remove(tr)
    for o, mb in BASIS.items():
        o.matrix_basis = mb
    for pb in arm.pose.bones:
        pb.matrix_basis = Matrix.Identity(4)
    bpy.context.view_layer.update()


for o in objs():
    if o.animation_data:
        o.animation_data.action = None
        for tr in list(o.animation_data.nla_tracks):
            o.animation_data.nla_tracks.remove(tr)
BASIS = {o: o.matrix_basis.copy() for o in objs()}       # file (rest) transforms
for pb in arm.pose.bones:
    pb.rotation_mode = "QUATERNION"
clear_animation()
REST_WORLD = {b.name: arm.matrix_world @ b.matrix_local for b in arm.data.bones}
clips = {}             # exported clip name -> {"frames": [...], "world": [{bone: Matrix}]}
want = CFG.get("animations", {})
for act in list(bpy.data.actions):
    out = want.get(act.name) or want.get(act.name.split("|")[-1].strip())
    if not out:
        continue
    bound = []
    for o in objs():
        slot = next((sl for sl in getattr(act, "slots", []) if sl.identifier == "OB" + o.name), None)
        if slot is None and o is arm and not getattr(act, "slots", None):
            slot = True                                     # legacy (slot-less) action
        if slot is None:
            continue
        if o.animation_data is None:
            o.animation_data_create()
        o.animation_data.action = act
        if slot is not True:
            o.animation_data.action_slot = slot
        bound.append(o.name)
    f0, f1 = int(round(act.frame_range[0])), int(round(act.frame_range[1]))
    rec = {"frames": list(range(f0, f1 + 1)), "world": []}
    for f in rec["frames"]:
        scene.frame_set(f)
        rec["world"].append({pb.name: arm.matrix_world @ pb.matrix for pb in arm.pose.bones})
    clips[out] = rec
    clear_animation()
    log("recorded clip", act.name, "->", out, "frames %d..%d" % (f0, f1), "objects", bound)
for act in list(bpy.data.actions):
    bpy.data.actions.remove(act)
scene.frame_set(0)
clear_animation()
if set(want.values()) - set(clips):
    log("WARNING: clips not found:", sorted(set(want.values()) - set(clips)))

# ============================================================================= 2b. clean up objects
# un-parent everything we keep (world transform preserved), then delete the rest
for o in [arm] + keep:
    mw = o.matrix_world.copy()
    o.parent = None
    o.matrix_world = mw
for o in list(objs()):
    if o is not arm and o not in keep:
        if o.type != "EMPTY":
            log("drop object", o.type, o.name)
        bpy.data.objects.remove(o, do_unlink=True)

# eye position from rigid eye meshes (measured before they are joined)
eye_cfg = CFG.get("eye", {})
eye_point = None
if eye_cfg.get("meshes"):
    pts = [bbox_centre(o) for o in keep if any(m in o.name for m in eye_cfg["meshes"])]
    eye_point = sum(pts, Vector()) / len(pts)

# rigid parts (eyes etc.) ride on one bone at 100 %
for name, bone in rigid.items():
    o = bpy.data.objects[name]
    for vg in list(o.vertex_groups):
        o.vertex_groups.remove(vg)
    o.vertex_groups.new(name=bone).add(list(range(len(o.data.vertices))), 1.0, "REPLACE")
    for m in list(o.modifiers):
        o.modifiers.remove(m)
    o.modifiers.new("Armature", "ARMATURE").object = arm
    log("rigid bind", name, "->", bone)

# bake object transforms into the meshes, then one mesh object
select_only(keep, keep[0])
bpy.ops.object.make_single_user(object=True, obdata=True)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
if len(keep) > 1:
    select_only(keep, max(keep, key=lambda o: len(o.data.vertices)))
    bpy.ops.object.join()
body = bpy.context.view_layer.objects.active
body.name = body.data.name = CID + "_body"
for m in list(body.modifiers):
    if m.type == "ARMATURE":
        body.modifiers.remove(m)
body.modifiers.new("Armature", "ARMATURE").object = arm
if body.data.shape_keys:
    log("shape keys", [k.name for k in body.data.shape_keys.key_blocks])
log("body tris", tri_count(body), "verts", len(body.data.vertices), "materials", [m.name for m in body.data.materials])

# ============================================================================= 4. rig surgery
cur = {b.name: b.name for b in arm.data.bones}    # source bone name -> current bone name
second_of = {}                                     # split tail-part name -> source bone it came from

eb = edit_mode(arm)
for child, parent in CFG.get("reparent", {}).items():
    eb[child].use_connect = False
    eb[child].parent = eb[parent]
    log("reparent", child, "->", parent)
splits = {}
for bone, spec in CFG.get("split", {}).items():
    e = eb[bone]
    first, second = spec["names"]
    at = spec.get("at", 0.5)
    head, tail = e.head.copy(), e.tail.copy()
    nb = eb.new(second)
    nb.head, nb.tail, nb.roll = head.lerp(tail, at), tail, e.roll
    for c in list(e.children):
        c.parent = nb
    nb.parent = e
    nb.use_connect = True
    e.tail = head.lerp(tail, at)
    splits[bone] = (head, tail, at, first, second)
object_mode()
# split weights: blend along the bone (smoothstep over +-15 % of its length)
for bone, (head, tail, at, first, second) in splits.items():
    h, t = np.array(arm.matrix_world @ head), np.array(arm.matrix_world @ tail)
    axis = t - h
    s = ((mesh_world_coords(body) - h) @ axis) / max(float(axis @ axis), 1e-12)
    x = np.clip((s - (at - 0.15)) / 0.30, 0.0, 1.0)
    blend = x * x * (3 - 2 * x)
    w = weights_matrix(body, [bone])[:, 0]
    vg, vg2 = body.vertex_groups[bone], body.vertex_groups.new(name=second)
    nz = np.nonzero(w > 0)[0]
    for i in nz:
        vg.add([int(i)], float(w[i] * (1 - blend[i])), "REPLACE")
        vg2.add([int(i)], float(w[i] * blend[i]), "REPLACE")
    arm.data.bones[bone].name = first              # renames the vertex group too
    cur[bone] = first
    second_of[second] = bone
    log("split", bone, "->", first, "+", second, "(%d weighted verts)" % len(nz))

# prune bones that deform nothing and are not referenced by the recipe
def recipe_names():
    out = [v for v in CFG["roles"].values() if v] + CFG.get("keep_bones", [])
    for ch in CFG.get("chains", {}).values():
        out += ch
    return out


def current(name):
    return cur.get(name, name)


referenced = {current(n) for n in recipe_names()}
Wall = weights_matrix(body, [b.name for b in arm.data.bones])
used = {b.name for k, b in enumerate(arm.data.bones) if (Wall[:, k] > 0).any()}
eb = edit_mode(arm)
doomed = {e.name for e in eb if e.name not in used and e.name not in referenced}
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
object_mode()
for vg in list(body.vertex_groups):
    if vg.name not in arm.data.bones:
        body.vertex_groups.remove(vg)
cur = {k: v for k, v in cur.items() if v not in doomed}
log("pruned %d non-deforming bones; %d left" % (len(doomed), len(arm.data.bones)))

# Godot-safe, unique names (vertex groups follow the bone rename)
cands = {b.name: sanitize(b.name) for b in arm.data.bones}
dupes = {v for v in cands.values() if list(cands.values()).count(v) > 1}
rename = {}
for old, new in cands.items():
    if new in dupes:
        new = re.sub(r"[^A-Za-z0-9_]", "_", old)     # keep the suffix to stay unique
    rename[old] = new
for old, new in rename.items():
    if old != new:
        arm.data.bones[old].name = new
cur = {k: rename.get(v, v) for k, v in cur.items()}
second_of = {rename.get(k, k): v for k, v in second_of.items()}
assert all(b.name in body.vertex_groups or b.name not in used for b in arm.data.bones)


def fin(name):
    """Final glb bone name for a recipe bone name (source name or split-part name)."""
    if name is None:
        return None
    n = cur.get(name, rename.get(name, name))
    if n not in arm.data.bones:
        raise SystemExit("recipe bone %r is missing after rig surgery" % name)
    return n


roles = {r: fin(CFG["roles"].get(r)) for r in ROLE_ORDER}
chains = {k: [fin(b) for b in v] for k, v in CFG.get("chains", {}).items()}
recorded = {v: k for k, v in cur.items()}           # final name -> name in the recording
log("roles", json.dumps(roles))

# ============================================================================= 5. orient + scale
bone_names = [b.name for b in arm.data.bones]
col = {n: i for i, n in enumerate(bone_names)}


def skin_data():
    return mesh_world_coords(body), weights_matrix(body, bone_names)


def descendants(name):
    out, st = [], [arm.data.bones[name]]
    while st:
        b = st.pop()
        out.append(b.name)
        st.extend(b.children)
    return out


def foot_verts(co, W, side):
    w = W[:, [col[n] for n in descendants(roles[side + "_foot"])]].sum(axis=1)
    return co[w > 0.3]


def head_verts(co, W, column=True):
    """Vertices of the head proper: skinned >= 50 % to the head bone, nothing
    from ear/hat bones, optionally only a centre column (ear tufts on top)."""
    w = W[:, col[roles["head"]]].copy()
    pats = [sanitize(x) for x in CFG.get("skull", {}).get("exclude", [])]
    ex = [n for n in bone_names if any(p and p in n for p in pats)]
    if ex:
        w[W[:, [col[n] for n in ex]].sum(axis=1) > 0.05] = 0.0
    pts = co[w >= 0.5]
    frac = CFG.get("skull", {}).get("column")
    if column and frac:
        hx = float(np.median(pts[:, 0]))
        half = float(np.percentile(np.abs(pts[:, 0] - hx), 95))
        pts = pts[np.abs(pts[:, 0] - hx) <= frac * half]
    return pts


co, W = skin_data()
lf, rf = foot_verts(co, W, "l"), foot_verts(co, W, "r")
sole = float(min(lf[:, 2].min(), rf[:, 2].min()))
centre = (lf[:, :2].mean(axis=0) + rf[:, :2].mean(axis=0)) / 2.0
skull = float(head_verts(co, W)[:, 2].max())


def joint(role):
    return np.array(arm.matrix_world @ arm.data.bones[roles[role]].head_local)


# facing: the shoulder + hip axis (right -> left) must point +X, which makes the
# character face -Y; the recipe can add a manual yaw on top
lat = (joint("l_upper_arm") - joint("r_upper_arm")) + (joint("l_upper_leg") - joint("r_upper_leg"))
yaw = -math.degrees(math.atan2(lat[1], lat[0])) + CFG.get("yaw_deg", 0.0)
# cross-check with the toes (ankle -> farthest foot vertex) after that yaw
fwd = np.zeros(2)
for side, pts in (("l", lf), ("r", rf)):
    ank = joint(side + "_foot")[:2]
    fwd += pts[np.argmax(np.linalg.norm(pts[:, :2] - ank, axis=1))][:2] - ank
c, s_ = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
fwd = np.array([c * fwd[0] - s_ * fwd[1], s_ * fwd[0] + c * fwd[1]])
toe_dev = math.degrees(math.atan2(fwd[0], -fwd[1]))
log("yaw %.1f deg (shoulder/hip axis); toes then point %.1f deg off -Y" % (yaw, toe_dev))
if abs(toe_dev) > 60:
    raise SystemExit("toes point backwards after orienting: left/right roles are probably swapped")
S = CFG["head_top"] / (skull - sole)
T = (Matrix.Scale(S, 4) @ Matrix.Rotation(math.radians(yaw), 4, "Z")
     @ Matrix.Translation((-centre[0], -centre[1], -sole)))
for o in (arm, body):
    o.matrix_world = T @ o.matrix_world
    select_only([o], o)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
body.parent = arm
body.matrix_parent_inverse = Matrix.Identity(4)
bpy.context.view_layer.update()
log("scale %.5f (skull %.4f, sole %.4f in source units)" % (S, skull, sole))

# left roles must sit at +X (the character's left when it faces -Y)
for r in ROLE_ORDER:
    if roles[r] and r[:2] in ("l_", "r_"):
        x = arm.data.bones[roles[r]].head_local.x
        if (r[0] == "l" and x < -0.005) or (r[0] == "r" and x > 0.005):
            log("WARNING: role %s (%s) is on the wrong side, x=%.3f" % (r, roles[r], x))

# ============================================================================= 6. budget + textures
n = tri_count(body)
if n > MAX_TRIS:
    if body.data.shape_keys:
        select_only([body], body)
        bpy.ops.object.shape_key_remove(all=True)
    dm = body.modifiers.new("decimate", "DECIMATE")
    dm.ratio = MAX_TRIS / n * 0.98
    dm.use_collapse_triangulate = True
    select_only([body], body)
    bpy.ops.object.modifier_move_to_index(modifier="decimate", index=0)
    bpy.ops.object.modifier_apply(modifier="decimate")
    log("decimated", n, "->", tri_count(body))
TRIS = tri_count(body)
# glTF/Godot skin with 4 influences per vertex: keep the strongest 4, renormalize
select_only([body], body)
bpy.ops.object.vertex_group_limit_total(group_select_mode="ALL", limit=4)
bpy.ops.object.vertex_group_normalize_all(group_select_mode="ALL", lock_active=False)
# vertex colours that no material reads would only bloat the file
uses_attr = any(n.type in ("VERTEX_COLOR", "ATTRIBUTE") for m in body.data.materials
                if m and m.node_tree for n in m.node_tree.nodes)
if not uses_attr:
    for ca in list(body.data.color_attributes):
        body.data.color_attributes.remove(ca)

png_imgs = set()       # normal maps and anything feeding alpha stay lossless
for mat in body.data.materials:
    if mat and mat.node_tree:
        for node in mat.node_tree.nodes:
            if node.type == "TEX_IMAGE" and node.image is not None:
                for out in node.outputs:
                    for link in out.links:
                        if link.to_node.type == "NORMAL_MAP" or link.to_socket.name in ("Normal", "Alpha"):
                            png_imgs.add(node.image.name)
TEX_TMP = tempfile.mkdtemp(prefix="bbd-tex-")
for img in list(bpy.data.images):
    if img.size[0] == 0 or img.users == 0:
        continue
    if max(img.size) > MAX_TEX:
        k = MAX_TEX / max(img.size)
        img.scale(max(1, int(img.size[0] * k)), max(1, int(img.size[1] * k)))
        log("texture", img.name, "resized to", tuple(img.size))
    if img.name in png_imgs:
        continue
    # colour data: re-encode as a packed JPEG (the glTF exporter keeps the
    # packed file's format in AUTO mode)
    path = os.path.join(TEX_TMP, re.sub(r"[^A-Za-z0-9_]", "_", img.name) + ".jpg")
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

# ============================================================================= 7. re-bake clips
rest = {b.name: b.matrix_local.copy() for b in arm.data.bones}
order = sorted(arm.data.bones, key=lambda b: len(b.parent_recursive))
for out, rec in clips.items():
    if arm.animation_data is None:
        arm.animation_data_create()
    act = bpy.data.actions.new(out)
    act.use_fake_user = True
    arm.animation_data.action = act
    prev_q = {}
    for fi, frame in enumerate(rec["frames"]):
        world = rec["world"][fi]
        target = {}
        for b in order:
            if b.name in second_of:                       # tail half of a split bone
                src_name, extra = second_of[b.name], True
            else:
                src_name, extra = recorded.get(b.name), False
            if src_name not in world:
                continue
            M = T @ world[src_name]
            R0 = T @ REST_WORLD[src_name]
            for i in range(3):                           # remove the global scale
                M.col[i].xyz = M.col[i].xyz / R0.col[i].xyz.length
            if extra:
                M = M @ rest[b.parent.name].inverted() @ rest[b.name]
            target[b.name] = M
        for b in order:
            if b.name not in target:
                continue
            p = b.parent
            if p is None:
                mb = rest[b.name].inverted() @ target[b.name]
            elif p.name in target:
                mb = (rest[p.name].inverted() @ rest[b.name]).inverted() @ target[p.name].inverted() @ target[b.name]
            else:
                continue
            loc, rot, sca = mb.decompose()
            if b.name in prev_q and prev_q[b.name].dot(rot) < 0:
                rot.negate()
            prev_q[b.name] = rot
            pb = arm.pose.bones[b.name]
            pb.location, pb.rotation_quaternion, pb.scale = loc, rot, sca
            for path in ("location", "rotation_quaternion", "scale"):
                pb.keyframe_insert(path, frame=frame, group=b.name)
    arm.animation_data.action = None
    log("baked clip", out, "(%d frames)" % len(rec["frames"]))
for pb in arm.pose.bones:
    pb.matrix_basis = Matrix.Identity(4)

# ============================================================================= 8. measure + export
arm.name = arm.data.name = CID + "_rig"
co, W = skin_data()


def seg_dist(P, a, b):
    ab = b - a
    t = np.clip(((P - a) @ ab) / max(float(ab @ ab), 1e-12), 0.0, 1.0)
    return np.linalg.norm(P - (a + t[:, None] * ab), axis=1)


# ragdoll / hitbox radius per role: median distance from the bone segment to
# the vertices that belong to it (weighted > 0.5, or the bone is the vertex's
# strongest influence at >= 0.3 - short bones in blended regions such as the
# hips rarely own a vertex outright)
dominant = np.argmax(W, axis=1)
radii = {}
for r in ROLE_ORDER:
    bn = roles[r]
    if not bn:
        continue
    w = W[:, col[bn]]
    sel = (w > 0.5) | ((dominant == col[bn]) & (w >= 0.3))
    if sel.sum() < 4:
        sel = w >= max(0.5 * w.max(), 1e-3)
    pts = co[sel]
    if len(pts):
        b = arm.data.bones[bn]
        radii[r] = round(float(np.median(seg_dist(pts, np.array(b.head_local), np.array(b.tail_local)))), 4)

hp = head_verts(co, W, column=False)
head_width = float(np.ptp(hp[:, 0]))
head_depth = float(np.ptp(hp[:, 1]))
hc = head_verts(co, W)
skull_pt = hc[np.argmax(hc[:, 2])]                       # Blender coords (x, y=-forward, z=up)
head_origin = arm.data.bones[roles["head"]].head_local

eye_h = None
if eye_cfg.get("bones"):
    eye_h = float(np.mean([arm.data.bones[fin(b)].head_local.z for b in eye_cfg["bones"]]))
elif eye_point is not None:
    eye_h = float((T @ eye_point).z)
elif eye_cfg.get("height"):
    eye_h = float(eye_cfg["height"])

ua, la = arm.data.bones[roles["l_upper_arm"]], arm.data.bones[roles["l_lower_arm"]]
d = (la.head_local - ua.head_local).normalized()
arm_angle = math.degrees(math.asin(max(-1.0, min(1.0, -d.z))))
rest_pose = CFG.get("rest_pose") or ("T" if arm_angle < 25 else "A")

# clips as NLA strips so the exporter writes one glTF animation per clip
for act in bpy.data.actions:
    tr = arm.animation_data.nla_tracks.new()
    tr.name = act.name
    tr.strips.new(act.name, int(act.frame_range[0]), act)
select_only([arm, body], arm)
props = bpy.ops.export_scene.gltf.get_rna_type().properties.keys()
kw = dict(filepath=OUT_GLB, export_format="GLB", use_selection=True, export_skins=True,
          export_animations=bool(clips), export_morph=bool(body.data.shape_keys), export_yup=True,
          export_apply=False, export_image_format="AUTO", export_cameras=False, export_lights=False)
for k, v in (("export_animation_mode", "ACTIONS"), ("export_image_quality", 88),
             ("export_jpeg_quality", 88), ("export_def_bones", False)):
    if k in props:
        kw[k] = v
bpy.ops.export_scene.gltf(**kw)
size = os.path.getsize(OUT_GLB)
shutil.rmtree(TEX_TMP, ignore_errors=True)
log("exported", OUT_GLB, "%.2f MB" % (size / 1e6), "tris", TRIS, "bones", len(arm.data.bones))

# notes use glTF/Godot coordinates: x = character's left, y = up, z = forward
auto = ("Facing +Z (glTF/Godot), +Y up, metres; soles at y=0, centred between the feet. "
        "Top of skull at y=%.3f (ears/hats excluded), crown point (x %.3f, y %.3f, z %.3f); head width %.3f m, depth %.3f m; "
        "head bone origin at (x %.3f, y %.3f, z %.3f). "
        "Rest pose %s (upper arm %.0f deg below horizontal). %d bones, %d triangles. "
        "Bone local axes follow Blender's convention (+Y along each bone towards its child)."
        % (CFG["head_top"], skull_pt[0], skull_pt[2], -skull_pt[1], head_width, head_depth,
           head_origin.x, head_origin.z, -head_origin.y, rest_pose, arm_angle, len(arm.data.bones), TRIS))
rig = {
    "id": CID,
    "display_name": CFG["display_name"],
    "species": CFG["species"],
    "head_top": CFG["head_top"],
    "eye_height": round(eye_h, 3) if eye_h is not None else None,
    "rest_pose": rest_pose,
    "bones": roles,
    "chains": chains,
    "radii": radii,
    "animations": list(clips.keys()),
    "notes": (CFG.get("notes", "") + " " + auto).strip(),
}
with open(OUT_RIG, "w") as f:
    json.dump(rig, f, indent=2)
    f.write("\n")
log("STATS", json.dumps({"tris": TRIS, "bones": len(arm.data.bones), "glb_bytes": size,
                         "head_width": round(head_width, 4), "arm_angle": round(arm_angle, 1),
                         "scale": S, "yaw": round(yaw, 1), "toe_dev": round(toe_dev, 1), "eye": eye_h}))
log("wrote", OUT_RIG)
