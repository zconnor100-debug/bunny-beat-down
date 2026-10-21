"""Render preview tiles of exported .glb files (Cycles, studio HDRI).

Imports the *exported* glb (so previews show exactly what ships), then renders:
    <id>_scale.png   the asset next to a 1 m reference capsule
    <id>_v1..v3.png  close-up turnaround (right side, front 3/4, rear 3/4 top)
or, with --hero, a few large close-ups of one asset.

    blender --background --python render_preview.py -- --out DIR [--tile 448] [--hero] a.glb b.glb
"""
from __future__ import annotations

import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
from bbd import util  # noqa: E402


def parse():
    args = util.script_args()
    out, tile, hero, files, samples = None, 448, False, [], 96
    global FOCUS, CAPSULE
    FOCUS = None
    it = iter(args)
    for a in it:
        if a == "--out":
            out = Path(next(it))
        elif a == "--tile":
            tile = int(next(it))
        elif a == "--samples":
            samples = int(next(it))
        elif a == "--hero":
            hero = True
        elif a == "--capsule":   # reference capsule height in metres (1.0 default, 1.1 = critter)
            CAPSULE = float(next(it))
        elif a == "--focus":  # xmin,ymin,zmin,xmax,ymax,zmax (Blender coords, after floor drop)
            FOCUS = [float(x) for x in next(it).split(",")]
        else:
            files.append(Path(a))
    return out, tile, hero, files, samples


def studio(tile, samples):
    sc = bpy.context.scene
    util.setup_cycles(samples)
    sc.cycles.use_denoising = True
    sc.render.resolution_x = sc.render.resolution_y = tile
    sc.render.film_transparent = True
    # PBR Neutral keeps albedo hues honest (AgX pushes saturated orange towards salmon)
    sc.view_settings.view_transform = "Khronos PBR Neutral"
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    w = bpy.data.worlds.new("studio")
    sc.world = w
    nt = w.node_tree
    env = nt.nodes.new("ShaderNodeTexEnvironment")
    env.image = bpy.data.images.load(util.cache_file(util.sources_meta()["studio_small_09"]["files"]["hdr"]))
    mp = nt.nodes.new("ShaderNodeMapping")
    tc = nt.nodes.new("ShaderNodeTexCoord")
    mp.inputs["Rotation"].default_value = (0, 0, math.radians(120))
    nt.links.new(tc.outputs["Generated"], mp.inputs["Vector"])
    nt.links.new(mp.outputs["Vector"], env.inputs["Vector"])
    bg = nt.nodes["Background"]
    bg.inputs["Strength"].default_value = 0.65
    nt.links.new(env.outputs["Color"], bg.inputs["Color"])
    # warm key + cool rim so forms read
    for name, loc, energy, color, size in (("key", (2.5, -2.5, 3.5), 420, (1.0, 0.94, 0.86), 2.0),
                                          ("rim", (-3.0, 2.5, 2.5), 260, (0.8, 0.88, 1.0), 2.5)):
        ld = bpy.data.lights.new(name, "AREA")
        ld.energy = energy
        ld.color = color
        ld.size = size
        lo = bpy.data.objects.new(name, ld)
        sc.collection.objects.link(lo)
        lo.location = loc
        lo.rotation_euler = (Vector((0, 0, 0)) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
    floor = bpy.data.objects.new("floor", bpy.data.meshes.new("floor"))
    sc.collection.objects.link(floor)
    import bmesh
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=20)
    bm.to_mesh(floor.data)
    bm.free()
    floor.is_shadow_catcher = True
    return floor


CAPSULE = 1.0


def capsule():
    import bmesh
    me = bpy.data.meshes.new("capsule")
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=32, v_segments=16, radius=0.15)
    for v in bm.verts:
        v.co.z += (CAPSULE - 0.30) + 0.15 if v.co.z > 0 else 0.15
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = True
    ob = bpy.data.objects.new("ref_capsule_1m", me)
    bpy.context.scene.collection.objects.link(ob)
    m = bpy.data.materials.new("capsule")
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (0.06, 0.075, 0.10, 1)
    b.inputs["Roughness"].default_value = 0.6
    me.materials.append(m)
    return ob


def import_glb(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(path))
    objs = [o for o in bpy.data.objects if o not in before]
    for o in objs:
        if o.type == "EMPTY":
            o.hide_render = True
    return objs


def bounds(objs):
    return util.world_bounds([o for o in objs if o.type == "MESH"])


def camera(target, dist, az_deg, el_deg, lens=50.0, ortho=None):
    sc = bpy.context.scene
    cd = bpy.data.cameras.new("cam")
    cd.lens = lens
    cd.clip_start = 0.005
    cd.clip_end = 100
    if ortho:
        cd.type = "ORTHO"
        cd.ortho_scale = ortho
    cam = bpy.data.objects.new("cam", cd)
    sc.collection.objects.link(cam)
    az, el = math.radians(az_deg), math.radians(el_deg)
    d = Vector((math.cos(el) * math.cos(az), math.cos(el) * math.sin(az), math.sin(el)))
    cam.location = target + d * dist
    cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
    sc.camera = cam
    return cam


FOCUS = None


def frame(objs, az, el, lens=50.0, pad=1.08):
    """Camera at (az, el) whose distance fits all 8 bounding-box corners in view."""
    lo, hi = bounds(objs)
    if FOCUS:
        lo, hi = Vector(FOCUS[:3]), Vector(FOCUS[3:])
    c = (lo + hi) / 2
    a, e = math.radians(az), math.radians(el)
    d = Vector((math.cos(e) * math.cos(a), math.cos(e) * math.sin(a), math.sin(e)))
    f = -d
    r = f.cross(Vector((0, 0, 1))).normalized()
    u = r.cross(f)
    t = 18.0 / lens  # tan(half fov) for a 36 mm sensor
    dist = 0.0
    for x in (lo.x, hi.x):
        for y in (lo.y, hi.y):
            for z in (lo.z, hi.z):
                q = Vector((x, y, z)) - c
                dist = max(dist, max(abs(q.dot(r)), abs(q.dot(u))) * pad / t + q.dot(d))
    return camera(c, max(dist, 0.05), az, el, lens)


def render(path):
    bpy.context.scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)


def drop_to_floor(objs):
    lo, hi = bounds(objs)
    roots = [o for o in objs if o.parent is None]
    for o in roots:
        o.location.z -= lo.z
    bpy.context.view_layer.update()


def main():
    out, tile, hero, files, samples = parse()
    out.mkdir(parents=True, exist_ok=True)
    for f in files:
        util.reset_scene()
        studio(tile * (2 if hero else 1), samples)
        objs = import_glb(f)
        key = f.stem
        drop_to_floor(objs)
        bpy.context.view_layer.update()
        if hero:
            for i, (az, el) in enumerate(((-60, 18), (30, 30), (-150, 12), (-90, 70))):
                cam = frame(objs, az, el, lens=70, pad=1.08)
                render(out / f"{key}_hero{i}.png")
                bpy.data.objects.remove(cam)
            continue
        # 1) scale reference next to a 1 m capsule
        lo, hi = bounds(objs)
        cap = capsule()
        cap.location = ((lo.x + hi.x) / 2, lo.y - 0.25, 0)
        bpy.context.view_layer.update()
        cam = frame(objs + [cap], 15, 10, lens=50, pad=1.05)
        render(out / f"{key}_scale.png")
        bpy.data.objects.remove(cam)
        cap.hide_render = True
        # 2-4) close-up turnaround
        for i, (az, el) in enumerate(((0, 6), (-55, 25), (135, 35))):
            cam = frame(objs, az, el, lens=60, pad=1.06)
            render(out / f"{key}_v{i + 1}.png")
            bpy.data.objects.remove(cam)


if __name__ == "__main__":
    main()
