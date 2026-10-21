"""Print what is inside a downloaded source model (run inside Blender).

    blender --background --factory-startup --python tools/env/inspect_source.py -- <file.glb|.gltf> [...]

For every object: name, type, parent, triangle count, world-space size,
materials and the images they use.  Used while writing env_recipes.json to
decide which sub-objects of a multi-variant pack become which game asset.
"""
import sys
from pathlib import Path

import bpy
from mathutils import Vector


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def tri_count(obj):
    me = obj.data
    me.calc_loop_triangles()
    return len(me.loop_triangles)


def world_bbox(obj):
    pts = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    return lo, hi


def mat_images(mat):
    out = []
    if mat and mat.use_nodes:
        for n in mat.node_tree.nodes:
            if n.type == "TEX_IMAGE" and n.image:
                links = [l.to_socket.name + "@" + l.to_node.name for l in n.outputs[0].links]
                out.append(f"{n.image.name}[{n.image.size[0]}x{n.image.size[1]}]->{','.join(links)}")
    return out


def inspect(path):
    reset()
    bpy.ops.import_scene.gltf(filepath=str(path))
    print(f"\n##### {path}")
    total = 0
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    for o in sorted(bpy.data.objects, key=lambda o: o.name):
        if o.type == "MESH":
            t = tri_count(o)
            total += t
            lo, hi = world_bbox(o)
            size = hi - lo
            mats = [m.name if m else None for m in o.data.materials]
            print(f"  MESH {o.name!r:40} parent={o.parent.name if o.parent else None!r:20} tris={t:7d} "
                  f"size=({size.x:.3f},{size.y:.3f},{size.z:.3f}) min_z={lo.z:.3f} center=({(lo.x+hi.x)/2:.2f},{(lo.y+hi.y)/2:.2f}) mats={mats}")
        else:
            print(f"  {o.type} {o.name!r} parent={o.parent.name if o.parent else None!r}")
    print(f"  total tris {total} in {len(meshes)} meshes")
    if meshes:
        lo = Vector((min(world_bbox(o)[0][i] for o in meshes) for i in range(3)))
        hi = Vector((max(world_bbox(o)[1][i] for o in meshes) for i in range(3)))
        print(f"  overall size ({hi.x-lo.x:.3f},{hi.y-lo.y:.3f},{hi.z-lo.z:.3f})  min_z={lo.z:.3f}")
    for m in bpy.data.materials:
        bm = getattr(m, "blend_method", "?")
        print(f"  MAT {m.name!r} blend={bm} images={mat_images(m)}")


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    for p in argv:
        inspect(Path(p))
