# Bunny Beat Down — dump the structure of a source model (headless Blender).
#
#   blender --background --python tools/characters/inspect_model.py -- <model.glb> [--pose] [--noguess] [--weights]
#
# Prints every object (type, parent, transform), the armature's bone tree
# (rest-pose head positions in world space), skinned meshes with triangle
# counts and vertex-group counts, materials/images and baked actions, plus the
# overall bounding box. Used to vet downloads before writing a normalize
# command line for them. --pose also prints the pose-space heads, which differ
# from the rest heads when the file's default pose is not its bind pose.
# --noguess imports with the node pose as rest instead of the guessed bind pose.
# --weights lists, per bone, how many vertices it deforms (finds dead control bones).
import sys

import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
SRC = argv[0]
SHOW_POSE = "--pose" in argv

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC, guess_original_bind_pose="--noguess" not in argv)
bpy.context.view_layer.update()

print("=" * 70)
print("FILE", SRC)
for o in bpy.context.scene.objects:
    print("OBJ %-40s %-9s parent=%-28s loc=%s rot=%s scale=%s" % (
        o.name[:40], o.type, (o.parent.name if o.parent else "-")[:28],
        tuple(round(c, 3) for c in o.location),
        tuple(round(c, 3) for c in o.rotation_euler),
        tuple(round(c, 3) for c in o.scale)))

for arm in [o for o in bpy.context.scene.objects if o.type == "ARMATURE"]:
    print("-" * 70)
    print("ARMATURE", arm.name, "bones", len(arm.data.bones))
    M = arm.matrix_world

    def walk(b, depth):
        h = M @ b.head_local
        t = M @ b.tail_local
        line = "  " * depth + "%s  head=(%.3f %.3f %.3f) tail=(%.3f %.3f %.3f)" % (b.name, *h, *t)
        if SHOW_POSE:
            pb = arm.pose.bones[b.name]
            ph = M @ pb.head
            line += "  pose=(%.3f %.3f %.3f)" % tuple(ph)
        print(line)
        for c in b.children:
            walk(c, depth + 1)

    for b in arm.data.bones:
        if b.parent is None:
            walk(b, 1)

print("-" * 70)
tot = 0
mn = Vector((1e9, 1e9, 1e9))
mx = -mn
dg = bpy.context.evaluated_depsgraph_get()
for o in [o for o in bpy.context.scene.objects if o.type == "MESH"]:
    o.data.calc_loop_triangles()
    n = len(o.data.loop_triangles)
    tot += n
    mods = [m.type + ("->" + m.object.name if getattr(m, "object", None) else "") for m in o.modifiers]
    sk = len(o.data.shape_keys.key_blocks) if o.data.shape_keys else 0
    print("MESH %-36s tris=%6d verts=%6d vgroups=%3d shapekeys=%d mats=%s mods=%s" % (
        o.name[:36], n, len(o.data.vertices), len(o.vertex_groups), sk,
        [m.name for m in o.data.materials if m], mods))
    oe = o.evaluated_get(dg)
    me = oe.to_mesh()
    for v in me.vertices:
        w = oe.matrix_world @ v.co
        mn = Vector(map(min, mn, w))
        mx = Vector(map(max, mx, w))
    oe.to_mesh_clear()
print("TOTAL TRIS", tot)
if "--weights" in argv:
    # which bones actually deform something: vertex count with any weight / weight > 0.5
    from collections import Counter
    anyw, strong = Counter(), Counter()
    for o in [o for o in bpy.context.scene.objects if o.type == "MESH"]:
        names = {g.index: g.name for g in o.vertex_groups}
        for v in o.data.vertices:
            for g in v.groups:
                if g.weight > 0.0:
                    anyw[names[g.group]] += 1
                if g.weight > 0.5:
                    strong[names[g.group]] += 1
    print("WEIGHTS (bone: verts with w>0 / w>0.5)")
    for n, c in sorted(anyw.items(), key=lambda kv: -kv[1]):
        print("  W %-40s %6d %6d" % (n[:40], c, strong[n]))
print("BOUNDS min=(%.3f %.3f %.3f) max=(%.3f %.3f %.3f) size=(%.3f %.3f %.3f)" % (*mn, *mx, *(mx - mn)))
print("-" * 70)
for img in bpy.data.images:
    print("IMAGE %-40s %dx%d" % (img.name[:40], img.size[0], img.size[1]))
for ac in bpy.data.actions:
    print("ACTION %-40s frames=%s" % (ac.name[:40], tuple(round(f, 1) for f in ac.frame_range)))
print("=" * 70)
