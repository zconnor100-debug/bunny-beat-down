# Bunny Beat Down — preview sheet of every skin variant.
#
#   blender --background --python tools/characters/render_skins.py -- <out.png> [id ...] [--res 240] [--head]
#
# For each character (default: all with a skins.json) the GLB is imported once
# and, for every entry of assets/characters/<id>/skins.json, each listed
# material's base-colour image is swapped for the skin's texture - by material
# name, the same way the game swaps StandardMaterial3D.albedo_texture. Each
# skin is rendered from the front three-quarter and the back three-quarter
# (orthographic, rest pose, EEVEE) and labelled; one row per character.
# --head renders a close-up of the head instead of the whole body.
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
RES = int(argv[argv.index("--res") + 1]) if "--res" in argv else 240
HEAD = "--head" in argv
ids = [a for a in argv[1:] if not a.startswith("--") and not a.isdigit()]
if not ids:
    with open(os.path.join(HERE, "roster.json")) as f:
        ids = [k for k in json.load(f) if not k.startswith("_")
               and os.path.exists(os.path.join(ROOT, "assets", "characters", k, "skins.json"))]
BG = np.array((0.93, 0.94, 0.95), np.float32)


def flat_mat(rgb):
    m = bpy.data.materials.new("label")
    m.use_nodes = True
    nt = m.node_tree
    for nd in list(nt.nodes):
        nt.nodes.remove(nd)
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (*rgb, 1.0)
    nt.links.new(em.outputs[0], nt.nodes.new("ShaderNodeOutputMaterial").inputs[0])
    return m


def render_character(cid):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    cdir = os.path.join(ROOT, "assets", "characters", cid)
    bpy.ops.import_scene.gltf(filepath=os.path.join(cdir, cid + ".glb"))
    for o in list(scene.objects):
        if o.type == "MESH" and o.name.lower().startswith("icosphere"):
            bpy.data.objects.remove(o, do_unlink=True)
        elif o.animation_data:
            o.animation_data.action = None
            for tr in list(o.animation_data.nla_tracks):
                o.animation_data.nla_tracks.remove(tr)
    for o in scene.objects:
        if o.type == "ARMATURE":
            for pb in o.pose.bones:
                pb.matrix_basis = Matrix.Identity(4)
    with open(os.path.join(cdir, "skins.json")) as f:
        skins = json.load(f)
    # the base-colour image node of every material, and its original image
    base_nodes = {}
    for m in bpy.data.materials:
        if not m.node_tree:
            continue
        for n in m.node_tree.nodes:
            if n.type == "BSDF_PRINCIPLED" and n.inputs["Base Color"].is_linked:
                src = n.inputs["Base Color"].links[0].from_node
                while src.type != "TEX_IMAGE" and src.inputs and any(i.is_linked for i in src.inputs):
                    src = next(i for i in src.inputs if i.is_linked).links[0].from_node
                if src.type == "TEX_IMAGE":
                    base_nodes[m.name] = (src, src.image)
    # framing
    V = []
    for o in scene.objects:
        if o.type == "MESH":
            V += [o.matrix_world @ v.co for v in o.data.vertices]
    V = np.array(V)
    h = V[:, 2].max()
    span = max(h, np.ptp(V[:, 0]) * 0.9, np.ptp(V[:, 1]) * 0.9) * 1.06
    zc = h * 0.5
    if HEAD:                                  # close-up of the top of the character
        span, zc = h * 0.42, h * 0.8
    scene.render.engine = "BLENDER_EEVEE"
    world = bpy.data.worlds.new("w")
    scene.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.55, 0.57, 0.6, 1.0)
    for rot, energy in (((math.radians(50), 0, math.radians(-30)), 3.0), ((math.radians(60), 0, math.radians(150)), 1.5)):
        ld = bpy.data.lights.new("sun", "SUN")
        ld.energy = energy
        lo = bpy.data.objects.new("sun", ld)
        lo.rotation_euler = rot
        scene.collection.objects.link(lo)
    scene.view_settings.view_transform = "Standard"
    scene.render.film_transparent = True
    scene.render.resolution_x = RES
    scene.render.resolution_y = RES
    cam_d = bpy.data.cameras.new("cam")
    cam_d.type = "ORTHO"
    cam_d.ortho_scale = span
    cam = bpy.data.objects.new("cam", cam_d)
    scene.collection.objects.link(cam)
    scene.camera = cam
    tiles = []
    for skin in skins:
        for mname, (node, orig) in base_nodes.items():
            rel = skin.get("albedo", {}).get(mname)
            node.image = bpy.data.images.load(os.path.join(cdir, rel), check_existing=True) if rel else orig
        views = []
        for yaw in (30.0, 210.0):
            a = math.radians(yaw)
            cam.rotation_euler = (math.pi / 2, 0, a)
            cam.location = (10 * math.sin(a), -10 * math.cos(a), zc)
            p = OUT + ".tile.png"
            scene.render.filepath = p
            bpy.ops.render.render(write_still=True)
            im = bpy.data.images.load(p)
            px = np.array(im.pixels[:], np.float32).reshape(im.size[1], im.size[0], 4)
            bpy.data.images.remove(im)
            os.remove(p)
            rgb = px[..., :3] * px[..., 3:4] + BG * (1 - px[..., 3:4])
            views.append(rgb)
        tiles.append((skin["name"], np.concatenate(views, axis=1)))
    return tiles


def label_strip(text_list, widths, height=26):
    """Render the skin names as a strip (Blender text, orthographic)."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    total = sum(widths)
    mat = flat_mat((0.15, 0.17, 0.2))
    x = 0
    for t, w in zip(text_list, widths):
        cu = bpy.data.curves.new("t", "FONT")
        cu.body = t
        cu.size = 16
        cu.align_x = "CENTER"
        o = bpy.data.objects.new("t", cu)
        o.data.materials.append(mat)
        o.location = (x + w / 2, 6, 0)
        scene.collection.objects.link(o)
        x += w
    cam_d = bpy.data.cameras.new("c")
    cam_d.type = "ORTHO"
    cam_d.ortho_scale = total
    cam = bpy.data.objects.new("c", cam_d)
    cam.location = (total / 2, height / 2, 50)
    scene.collection.objects.link(cam)
    scene.camera = cam
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.render.film_transparent = True
    scene.render.resolution_x = total
    scene.render.resolution_y = height
    scene.view_settings.view_transform = "Standard"
    p = OUT + ".label.png"
    scene.render.filepath = p
    bpy.ops.render.render(write_still=True)
    im = bpy.data.images.load(p)
    px = np.array(im.pixels[:], np.float32).reshape(im.size[1], im.size[0], 4)
    os.remove(p)
    return px[..., :3] * px[..., 3:4] + BG * (1 - px[..., 3:4])


rows = []
for cid in ids:
    tiles = render_character(cid)
    names = [cid + ": " + tiles[0][0]] + [t[0] for t in tiles[1:]]
    body = np.concatenate([t[1] for t in tiles], axis=1)
    lab = label_strip(names, [t[1].shape[1] for t in tiles])
    # label strip sits below the renders (image rows are bottom-up)
    rows.append(np.concatenate([lab, body], axis=0))
    print("SKINS_RENDERED", cid, len(tiles))
W = max(r.shape[1] for r in rows)
rows = [np.concatenate([r, np.broadcast_to(BG, (r.shape[0], W - r.shape[1], 3))], axis=1) for r in rows]
sheet = np.concatenate(rows[::-1], axis=0)              # first character on top
img = bpy.data.images.new("sheet", sheet.shape[1], sheet.shape[0], alpha=False)
px = np.ones((sheet.shape[0], sheet.shape[1], 4), np.float32)
px[..., :3] = sheet
img.pixels.foreach_set(px.ravel())
img.filepath_raw = OUT
img.file_format = "PNG"
img.save()
print("SKINS_SHEET", OUT, sheet.shape[1], "x", sheet.shape[0])
