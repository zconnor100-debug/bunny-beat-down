# Bunny Beat Down — all characters side by side at true relative scale.
#
#   blender --background --python tools/characters/render_lineup.py -- <out.png> [id id ...] [--res 2400]
#
# Loads assets/characters/<id>/<id>.glb for every id (default: every folder
# with a GLB, roster.json order), stands them on a metre grid (fine line every
# 0.1 m, strong line every 0.5 m) in a slight three-quarter orthographic view
# (heights stay true) so ears, snouts and tails read, and labels each with its
# name and a green tick at its head_top. All models are in their rest pose.
import json
import math
import os
import sys

import bpy
import numpy as np
from mathutils import Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
argv = sys.argv[sys.argv.index("--") + 1:]
OUT = argv[0]
RES = int(argv[argv.index("--res") + 1]) if "--res" in argv else 2400
ids = [a for a in argv[1:] if not a.startswith("--") and not a.isdigit()]
if not ids:
    with open(os.path.join(HERE, "roster.json")) as f:
        order = [k for k in json.load(f) if not k.startswith("_")]
    ids = [i for i in order if os.path.exists(os.path.join(ROOT, "assets", "characters", i, i + ".glb"))]
BG = (0.93, 0.94, 0.95)

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene


def flat_mat(name, rgb):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    for nd in list(nt.nodes):
        nt.nodes.remove(nd)
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (*rgb, 1.0)
    nt.links.new(em.outputs[0], nt.nodes.new("ShaderNodeOutputMaterial").inputs[0])
    return m


M_FINE, M_MAJOR = flat_mat("fine", (0.66, 0.69, 0.72)), flat_mat("major", (0.2, 0.22, 0.26))
M_TOP = flat_mat("top", (0.05, 0.6, 0.15))


def box(center, size, mat):
    me = bpy.data.meshes.new("b")
    sx, sy, sz = (s / 2 for s in size)
    vs = [(x * sx, y * sy, z * sz) for x in (-1, 1) for y in (-1, 1) for z in (-1, 1)]
    fs = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    me.from_pydata(vs, [], fs)
    me.materials.append(mat)
    o = bpy.data.objects.new("b", me)
    o.location = center
    o.visible_shadow = False
    scene.collection.objects.link(o)
    return o


def text(body, loc, size, mat, align="LEFT"):
    cu = bpy.data.curves.new("t", "FONT")
    cu.body = body
    cu.size = size
    cu.align_x = align
    o = bpy.data.objects.new("t", cu)
    o.data.materials.append(mat)
    o.location = loc
    o.rotation_euler = (math.pi / 2, 0, 0)
    o.visible_shadow = False
    scene.collection.objects.link(o)
    return o


# ---------------------------------------------------------------- characters
x = 0.32                      # room on the left for the grid labels
tops, placed = [], []
for cid in ids:
    glb = os.path.join(ROOT, "assets", "characters", cid, cid + ".glb")
    with open(os.path.join(ROOT, "assets", "characters", cid, cid + ".rig.json")) as f:
        rig = json.load(f)
    before = set(scene.objects)
    bpy.ops.import_scene.gltf(filepath=glb)
    new = [o for o in scene.objects if o not in before]
    for o in list(new):                     # the importer's bone-display shape
        if o.type == "MESH" and o.name.lower().startswith("icosphere"):
            new.remove(o)
            bpy.data.objects.remove(o, do_unlink=True)
    for o in new:
        if o.animation_data:
            o.animation_data.action = None
            for tr in list(o.animation_data.nla_tracks):
                o.animation_data.nla_tracks.remove(tr)
        if o.type == "ARMATURE":
            for pb in o.pose.bones:
                pb.matrix_basis = Matrix.Identity(4)
    bpy.context.view_layer.update()
    pts = []
    for o in new:
        if o.type == "MESH":
            co = np.array([o.matrix_world @ v.co for v in o.data.vertices])
            pts.append(co)
    P = np.concatenate(pts)
    half = max(abs(P[:, 0]).max(), 0.18) + 0.06
    x += half
    roots = [o for o in new if o.parent is None]
    for o in roots:
        o.location.x += x
    placed.append((cid, rig, x, float(P[:, 2].max())))
    x += half

# ---------------------------------------------------------------- grid, labels
width = x
top = max(p[3] for p in placed) + 0.25
lw = 0.004
for i in range(int(math.ceil(top / 0.1)) + 1):
    z = i * 0.1
    major = i % 5 == 0
    box((width / 2, 1.5, z), (width + 0.4, lw, lw * (2.4 if major else 1.0)), M_MAJOR if major else M_FINE)
    if major:
        text("%.1f m" % z, (0.0, 1.4, z + 0.01), 0.05, M_MAJOR)
for cid, rig, cx, h in placed:
    ht = rig["head_top"]
    # head_top tick just right of the head, at the character's own depth
    box((cx + 0.26, 0.0, ht), (0.14, lw, lw * 2.5), M_TOP)
    text(rig["display_name"], (cx, 0.0, -0.11), 0.065, M_MAJOR, "CENTER")
    text("skull %.2f m" % ht, (cx, 0.0, -0.19), 0.045, M_MAJOR, "CENTER")

# ---------------------------------------------------------------- render
scene.render.engine = "BLENDER_EEVEE"
world = bpy.data.worlds.new("w")
scene.world = world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.55, 0.57, 0.6, 1.0)
for rot, energy in (((math.radians(50), 0, math.radians(-30)), 3.0), ((math.radians(60), 0, math.radians(150)), 1.2)):
    ld = bpy.data.lights.new("sun", "SUN")
    ld.energy = energy
    lo = bpy.data.objects.new("sun", ld)
    lo.rotation_euler = rot
    scene.collection.objects.link(lo)
scene.view_settings.view_transform = "Standard"
scene.render.film_transparent = True
aspect = (width + 0.3) / (top + 0.5)
scene.render.resolution_x = RES
scene.render.resolution_y = int(RES / aspect)
cam_d = bpy.data.cameras.new("cam")
cam_d.type = "ORTHO"
cam_d.ortho_scale = width + 0.3
cam = bpy.data.objects.new("cam", cam_d)
scene.collection.objects.link(cam)
scene.camera = cam
# slight three-quarter: 15 deg around the vertical (characters face -Y)
yaw = math.radians(15)
cam.rotation_euler = (math.pi / 2, 0, yaw)
cx, cz = width / 2 + 0.25, (top - 0.3) / 2
d = 20.0
cam.location = (cx + d * math.sin(yaw), -d * math.cos(yaw), cz)
cam_d.clip_end = 100
tmp = OUT + ".raw.png"
scene.render.filepath = tmp
bpy.ops.render.render(write_still=True)
im = bpy.data.images.load(tmp)
w, h = im.size
a = np.array(im.pixels[:], dtype=np.float32).reshape(h, w, 4)
rgb = a[..., :3] * a[..., 3:4] + np.array(BG, np.float32) * (1 - a[..., 3:4])
out = bpy.data.images.new("lineup", w, h, alpha=False)
out.pixels = np.concatenate([rgb, np.ones((h, w, 1), np.float32)], axis=2).ravel()
out.filepath_raw = OUT
out.file_format = "PNG"
out.save()
os.remove(tmp)
print("LINEUP", OUT, ids)
