"""Build the project-owned test mannequin used by automated tests and as a fallback rig.

    blender --background --python tools/testrig/make_test_critter.py -- assets/test/test_critter.glb

A deliberately simple critter: rigidly-skinned capsules on a standard biped skeleton,
plus 2-bone ear chains and a 2-bone tail, so the procedural animator, ragdoll and
dismemberment code can be exercised without any third-party model.
Blender axes: Z up, the critter faces -Y (glTF/Godot +Z).
"""
import sys
import bpy
from mathutils import Vector

out = sys.argv[sys.argv.index("--") + 1]
bpy.ops.wm.read_factory_settings(use_empty=True)

# name: (head, tail, parent, radius)   -- metres, Blender coordinates
BONES = {
    "hips":        ((0, 0, 0.40), (0, 0, 0.50), None, 0.13),
    "spine":       ((0, 0, 0.50), (0, 0, 0.60), "hips", 0.12),
    "chest":       ((0, 0, 0.60), (0, 0, 0.71), "spine", 0.13),
    "neck":        ((0, 0, 0.71), (0, 0, 0.76), "chest", 0.05),
    "head":        ((0, 0, 0.76), (0, 0, 0.95), "neck", 0.11),
    "ear_l1":      ((0.05, 0.01, 0.91), (0.07, 0.02, 1.03), "head", 0.025),
    "ear_l2":      ((0.07, 0.02, 1.03), (0.09, 0.03, 1.16), "ear_l1", 0.022),
    "ear_r1":      ((-0.05, 0.01, 0.91), (-0.07, 0.02, 1.03), "head", 0.025),
    "ear_r2":      ((-0.07, 0.02, 1.03), (-0.09, 0.03, 1.16), "ear_r1", 0.022),
    "tail1":       ((0, 0.10, 0.44), (0, 0.15, 0.47), "hips", 0.035),
    "tail2":       ((0, 0.15, 0.47), (0, 0.19, 0.52), "tail1", 0.04),
    "upper_arm_l": ((0.12, 0, 0.69), (0.26, 0, 0.69), "chest", 0.04),
    "lower_arm_l": ((0.26, 0, 0.69), (0.38, 0, 0.69), "upper_arm_l", 0.035),
    "hand_l":      ((0.38, 0, 0.69), (0.44, 0, 0.69), "lower_arm_l", 0.03),
    "upper_arm_r": ((-0.12, 0, 0.69), (-0.26, 0, 0.69), "chest", 0.04),
    "lower_arm_r": ((-0.26, 0, 0.69), (-0.38, 0, 0.69), "upper_arm_r", 0.035),
    "hand_r":      ((-0.38, 0, 0.69), (-0.44, 0, 0.69), "lower_arm_r", 0.03),
    "upper_leg_l": ((0.07, 0, 0.40), (0.07, 0, 0.22), "hips", 0.05),
    "lower_leg_l": ((0.07, 0, 0.22), (0.07, 0, 0.05), "upper_leg_l", 0.045),
    "foot_l":      ((0.07, 0, 0.05), (0.07, -0.09, 0.02), "lower_leg_l", 0.035),
    "upper_leg_r": ((-0.07, 0, 0.40), (-0.07, 0, 0.22), "hips", 0.05),
    "lower_leg_r": ((-0.07, 0, 0.22), (-0.07, 0, 0.05), "upper_leg_r", 0.045),
    "foot_r":      ((-0.07, 0, 0.05), (-0.07, -0.09, 0.02), "lower_leg_r", 0.035),
}

arm_data = bpy.data.armatures.new("TestRig")
arm = bpy.data.objects.new("TestRig", arm_data)
bpy.context.scene.collection.objects.link(arm)
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode="EDIT")
for name, (h, t, parent, _r) in BONES.items():
    eb = arm_data.edit_bones.new(name)
    eb.head, eb.tail = Vector(h), Vector(t)
    if parent:
        eb.parent = arm_data.edit_bones[parent]
        eb.use_connect = False
bpy.ops.object.mode_set(mode="OBJECT")

fur = bpy.data.materials.new("Fur")
fur.use_nodes = True
fur.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.75, 0.68, 0.6, 1)
fur.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.85

pieces = []
for name, (h, t, _p, r) in BONES.items():
    h, t = Vector(h), Vector(t)
    length = (t - h).length
    bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=10, radius=1.0)
    ob = bpy.context.active_object
    ob.name = "piece_" + name
    # an ellipsoid spanning the bone, slightly overlapping its neighbours
    ob.scale = (r, r, length * 0.5 + r * 0.6)
    ob.location = (h + t) * 0.5
    ob.rotation_mode = "QUATERNION"
    ob.rotation_quaternion = Vector((0, 0, 1)).rotation_difference((t - h).normalized())
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    vg = ob.vertex_groups.new(name=name)
    vg.add(list(range(len(ob.data.vertices))), 1.0, "REPLACE")
    ob.data.materials.append(fur)
    bpy.ops.object.shade_smooth()
    pieces.append(ob)

bpy.ops.object.select_all(action="DESELECT")
for ob in pieces:
    ob.select_set(True)
bpy.context.view_layer.objects.active = pieces[0]
bpy.ops.object.join()
body = bpy.context.active_object
body.name = "TestCritterBody"
body.parent = arm
mod = body.modifiers.new("Armature", "ARMATURE")
mod.object = arm

bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", export_animations=False,
                          export_skins=True, export_yup=True)
print("wrote", out)
