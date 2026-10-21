# Bunny Beat Down — front + side orthographic preview of a character GLB.
#
#   blender --background --python tools/characters/render_preview.py -- \
#           <model.glb> <out.png> [--title "Bun"] [--res 640] [--source] [--noguess]
#           [--bones] [--head] [--workbench]
#
# Normalized characters (the default) are drawn on a metre grid: a fine line
# every 0.1 m, a strong line every 0.5 m, a red 1 m reference bar, and - when
# <model>.rig.json sits next to the GLB - a green line at head_top and a short
# blue line at eye_height. Left half: FRONT view (camera in front of the face,
# the character's left is image right). Right half: the character's LEFT side
# (it faces image left).
#   --source     un-normalized download: grid scaled to the model's bounds
#                (labels in % of height)
#   --noguess    import with the file's node pose as rest (raw downloads)
#   --bones      overlay the armature as thin orange sticks
#   --head       close-up of the head (top ~40 %) with a 1 cm grid, for
#                measuring eye height / skull top
#   --workbench  flat Workbench shading instead of EEVEE
#   --anim NAME --frame F   pose the model with baked clip NAME at frame F
#                (checks re-baked animations); otherwise the rest pose is shown
import json
import math
import os
import sys

import bpy
import numpy as np
from mathutils import Matrix, Vector

argv = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT = argv[0], argv[1]
TITLE = argv[argv.index("--title") + 1] if "--title" in argv else os.path.basename(SRC)
RES = int(argv[argv.index("--res") + 1]) if "--res" in argv else 640
SOURCE = "--source" in argv
BONES = "--bones" in argv
HEAD = "--head" in argv
BG = (0.93, 0.94, 0.95)

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC, guess_original_bind_pose="--noguess" not in argv)
scene = bpy.context.scene

# rest pose: the importer assigns the first clip (and stashes others in NLA)
ANIM = argv[argv.index("--anim") + 1] if "--anim" in argv else None
for o in scene.objects:
    if o.animation_data:
        o.animation_data.action = None
        for tr in list(o.animation_data.nla_tracks):
            o.animation_data.nla_tracks.remove(tr)
    if o.type == "ARMATURE":
        for pb in o.pose.bones:
            pb.matrix_basis = Matrix.Identity(4)
        if ANIM:
            act = next(a for a in bpy.data.actions if a.name == ANIM or a.name.startswith(ANIM + "_"))
            o.animation_data.action = act
            slot = next((sl for sl in getattr(act, "slots", []) if sl.identifier == "OB" + o.name), None)
            if slot is not None:
                o.animation_data.action_slot = slot
            scene.frame_set(int(argv[argv.index("--frame") + 1]) if "--frame" in argv else 0)
# stray Sketchfab helper geometry never belongs in a preview
for o in list(scene.objects):
    if o.type == "MESH" and o.name.lower().startswith("icosphere"):
        bpy.data.objects.remove(o, do_unlink=True)

rig = None
rig_path = os.path.splitext(SRC)[0] + ".rig.json"
if not SOURCE and os.path.exists(rig_path):
    with open(rig_path) as f:
        rig = json.load(f)


def world_verts():
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    out = []
    for o in scene.objects:
        if o.type != "MESH":
            continue
        oe = o.evaluated_get(dg)
        me = oe.to_mesh()
        if len(me.vertices):
            co = np.empty(len(me.vertices) * 3)
            me.vertices.foreach_get("co", co)
            co = co.reshape(-1, 3)
            M = np.array(oe.matrix_world)
            out.append(co @ M[:3, :3].T + M[:3, 3])
        oe.to_mesh_clear()
    return np.concatenate(out)


V = world_verts()
mn, mx = V.min(0), V.max(0)
z0 = float(mn[2]) if SOURCE else 0.0
H = float(mx[2]) - z0
unit = H / 10.0 if SOURCE else 1.0            # length the "1 m" grid stands for
cx, cy = (float(mn[0] + mx[0]) / 2, float(mn[1] + mx[1]) / 2) if SOURCE else (0.0, 0.0)
span = max(H, float(mx[0] - mn[0]), float(mx[1] - mn[1])) * 1.15 + 0.1 * unit
zc = z0 + span * 0.44
step = 0.1 * unit
if HEAD:
    span = H * 0.42
    zc = z0 + H - span * 0.36
    step = 0.01 * unit


# ---------------------------------------------------------------- helpers
def flat_mat(name, rgb):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*rgb, 1.0)
    m.use_nodes = True
    nt = m.node_tree
    for nd in list(nt.nodes):
        nt.nodes.remove(nd)
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (*rgb, 1.0)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(em.outputs[0], out.inputs[0])
    return m


M_FINE = flat_mat("grid_fine", (0.62, 0.65, 0.69))
M_MAJOR = flat_mat("grid_major", (0.2, 0.22, 0.26))
M_REF = flat_mat("ref_red", (0.85, 0.1, 0.08))
M_TOP = flat_mat("ref_green", (0.05, 0.6, 0.15))
M_EYE = flat_mat("ref_blue", (0.1, 0.35, 0.9))
M_BONE = flat_mat("bone", (1.0, 0.45, 0.0))


def box(name, center, size, mat):
    me = bpy.data.meshes.new(name)
    sx, sy, sz = (s / 2 for s in size)
    vs = [(x * sx, y * sy, z * sz) for x in (-1, 1) for y in (-1, 1) for z in (-1, 1)]
    fs = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    me.from_pydata(vs, [], fs)
    me.materials.append(mat)
    o = bpy.data.objects.new(name, me)
    o.location = center
    o.visible_shadow = False
    scene.collection.objects.link(o)
    return o


def text(body, loc, size, rot, mat):
    cu = bpy.data.curves.new("txt", "FONT")
    cu.body = body
    cu.size = size
    o = bpy.data.objects.new("txt", cu)
    o.data.materials.append(mat)
    o.location = loc
    o.rotation_euler = rot
    o.visible_shadow = False
    scene.collection.objects.link(o)
    return o


# ---------------------------------------------------------------- grid + markers
lw = span / 700.0
FRONT, SIDE = (math.pi / 2, 0, 0), (math.pi / 2, 0, math.pi / 2)
zlo, zhi = zc - span * 0.65, zc + span * 0.65
for i in range(int(math.floor((max(zlo, z0) - z0) / step)), int(math.ceil((zhi - z0) / step)) + 1):
    z = z0 + i * step
    major = (i % 5 == 0)
    mat, w = (M_MAJOR, lw * 2.2) if major else (M_FINE, lw)
    box("gf", (cx, cy + span * 0.6, z), (span * 1.2, lw, w), mat)          # behind the front view
    box("gs", (cx - span * 0.6, cy, z), (lw, span * 1.2, w), mat)          # behind the side view
    if major:
        if SOURCE:
            lab = "%d%%" % round(i * step / unit * 10)
        else:
            lab = ("%.2f m" if HEAD else "%.1f m") % (i * step)
        text(lab, (cx - span * 0.48, cy + span * 0.55, z + lw * 3), span * 0.025, FRONT, M_MAJOR)
        text(lab, (cx - span * 0.55, cy + span * 0.38, z + lw * 3), span * 0.025, SIDE, M_MAJOR)
if not HEAD:
    bar = 10.0 * unit if SOURCE else 1.0
    box("ref", (cx + span * 0.42, cy + span * 0.5, z0 + bar / 2), (lw * 6, lw, bar), M_REF)
    box("ref", (cx - span * 0.5, cy - span * 0.42, z0 + bar / 2), (lw, lw * 6, bar), M_REF)
if rig:
    ht, eh = rig["head_top"], rig.get("eye_height")
    box("ht", (cx, cy + span * 0.55, ht), (span * 0.5, lw, lw * 2.5), M_TOP)
    box("ht", (cx - span * 0.55, cy, ht), (lw, span * 0.5, lw * 2.5), M_TOP)
    if eh:
        box("eh", (cx + span * 0.32, cy + span * 0.55, eh), (span * 0.16, lw, lw * 2.5), M_EYE)
        box("eh", (cx - span * 0.55, cy - span * 0.32, eh), (lw, span * 0.16, lw * 2.5), M_EYE)
title_o = text(TITLE, (cx - span * 0.48, cy + span * 0.55, zc + span * 0.52), span * 0.045, FRONT, M_MAJOR)

if BONES:
    for arm in [o for o in scene.objects if o.type == "ARMATURE"]:
        for pb in arm.pose.bones:
            h, t = arm.matrix_world @ pb.head, arm.matrix_world @ pb.tail
            d = t - h
            if d.length < 1e-6:
                continue
            o = box("bone", (h + t) / 2, (lw * 2.5, lw * 2.5, d.length), M_BONE)
            o.rotation_mode = "QUATERNION"
            o.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(d)

# ---------------------------------------------------------------- render setup
if "--workbench" in argv:
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "TEXTURE"
else:
    scene.render.engine = "BLENDER_EEVEE"
    world = bpy.data.worlds.new("w")
    scene.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.55, 0.57, 0.6, 1.0)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 1.0
    for rot, energy in (((math.radians(50), 0, math.radians(-30)), 3.0),      # key: front-left, above
                        ((math.radians(60), 0, math.radians(150)), 1.2)):     # rim from behind
        ld = bpy.data.lights.new("sun", "SUN")
        ld.energy = energy
        ld.angle = math.radians(8)
        lo = bpy.data.objects.new("sun", ld)
        lo.rotation_euler = rot
        scene.collection.objects.link(lo)
scene.display_settings.display_device = "sRGB"
scene.view_settings.view_transform = "Standard"
scene.render.resolution_x = RES
scene.render.resolution_y = int(RES * 1.25)
scene.render.film_transparent = True

cam_d = bpy.data.cameras.new("cam")
cam_d.type = "ORTHO"
cam_d.ortho_scale = span * 1.25
cam_d.clip_end = span * 20
cam = bpy.data.objects.new("cam", cam_d)
scene.collection.objects.link(cam)
scene.camera = cam

shots = []
for view, loc, rot in (("front", (cx, cy - span * 5, zc), (math.pi / 2, 0, 0)),
                       ("side", (cx + span * 5, cy, zc), (math.pi / 2, 0, math.pi / 2))):
    cam.location, cam.rotation_euler = loc, rot
    title_o.hide_render = view != "front"
    p = OUT + "." + view + ".png"
    scene.render.filepath = p
    bpy.ops.render.render(write_still=True)
    shots.append(p)

# stitch the two renders side by side over a light background
imgs = [bpy.data.images.load(p) for p in shots]
w, h = imgs[0].size
px = []
for im in imgs:
    a = np.array(im.pixels[:], dtype=np.float32).reshape(h, w, 4)
    rgb = a[..., :3] * a[..., 3:4] + np.array(BG, dtype=np.float32) * (1 - a[..., 3:4])
    px.append(np.concatenate([rgb, np.ones((h, w, 1), np.float32)], axis=2))
sep = np.zeros((h, 4, 4), dtype=np.float32)
sep[..., 3] = 1.0
both = np.concatenate([px[0], sep, px[1]], axis=1)
out = bpy.data.images.new("preview", both.shape[1], h, alpha=False)
out.pixels = both.ravel()
out.filepath_raw = OUT
out.file_format = "PNG"
out.save()
for p in shots:
    os.remove(p)
print("PREVIEW", OUT)
