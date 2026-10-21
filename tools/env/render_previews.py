"""Render a scale-check preview of every environment GLB (runs inside Blender).

    blender --background --factory-startup --python tools/env/render_previews.py -- [ids...]

Each model from assets/env/manifest.json is rendered with Cycles next to a 1 m
tall orange capsule (the size of a critter) on a ground disc, lit by the
project's sky HDRI plus a sun.  Models taller than 12 m also get a second,
critter's-eye close-up of their base (shown as an inset on the sheet).
Frames go to /tmp/bbd-envpreview/<id>.png and <id>_base.png; make_preview_sheet.py
assembles them into assets/env/preview_sheet.png.
"""
from __future__ import annotations

import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector

TOOLS = Path(__file__).resolve().parent
ROOT = TOOLS.parents[1]
OUT = Path("/tmp/bbd-envpreview")
RES = 512


def setup_render(scene):
    scene.render.engine = "CYCLES"
    prefs = bpy.context.preferences.addons["cycles"].preferences
    for backend in ("OPTIX", "CUDA"):
        try:
            prefs.compute_device_type = backend
            prefs.get_devices()
            devs = [d for d in prefs.devices if d.type == backend]
            if devs:
                for d in devs:
                    d.use = True
                scene.cycles.device = "GPU"
                break
        except TypeError:
            continue
    scene.cycles.samples = 64
    scene.cycles.use_denoising = True
    scene.cycles.max_bounces = 6
    scene.cycles.transparent_max_bounces = 32  # stacked foliage cards
    scene.render.resolution_x = RES
    scene.render.resolution_y = RES
    scene.render.film_transparent = False
    scene.view_settings.view_transform = "AgX"
    scene.view_settings.look = "AgX - Medium High Contrast"


def world(scene):
    w = bpy.data.worlds.new("sky")
    scene.world = w
    nt = w.node_tree
    bg = nt.nodes["Background"]
    hdr = sorted((ROOT / "assets" / "sky").glob("*2k.hdr")) or sorted(
        (ROOT / "tools" / "_cache" / "env").glob("ph_*puresky/*_2k.hdr"))
    if hdr:
        env = nt.nodes.new("ShaderNodeTexEnvironment")
        env.image = bpy.data.images.load(str(hdr[0]))
        nt.links.new(env.outputs["Color"], bg.inputs["Color"])
        bg.inputs["Strength"].default_value = 0.8
    else:
        bg.inputs["Color"].default_value = (0.6, 0.75, 0.95, 1)
    sun = bpy.data.lights.new("sun", "SUN")
    sun.energy = 3.5
    sun.angle = math.radians(2.0)
    so = bpy.data.objects.new("sun", sun)
    so.rotation_euler = (math.radians(50), math.radians(10), math.radians(-35))
    scene.collection.objects.link(so)


def ground(scene, radius):
    bpy.ops.mesh.primitive_circle_add(vertices=64, radius=radius, fill_type="NGON", location=(0, 0, 0))
    g = bpy.context.active_object
    m = bpy.data.materials.new("ground")
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    tex_dir = ROOT / "assets" / "textures" / "forest_floor"
    if (tex_dir / "albedo.jpg").exists():
        t = nt.nodes.new("ShaderNodeTexImage")
        t.image = bpy.data.images.load(str(tex_dir / "albedo.jpg"))
        mapping = nt.nodes.new("ShaderNodeMapping")
        coord = nt.nodes.new("ShaderNodeTexCoord")
        s = radius / 3.0  # ~3 m per texture tile
        mapping.inputs["Scale"].default_value = (s, s, s)
        nt.links.new(coord.outputs["UV"], mapping.inputs["Vector"])
        nt.links.new(mapping.outputs["Vector"], t.inputs["Vector"])
        nt.links.new(t.outputs["Color"], b.inputs["Base Color"])
    else:
        b.inputs["Base Color"].default_value = (0.18, 0.22, 0.12, 1)
    b.inputs["Roughness"].default_value = 0.95
    g.data.materials.append(m)
    # simple planar UVs for the disc
    uv = g.data.uv_layers.new()
    for loop in g.data.loops:
        co = g.data.vertices[loop.vertex_index].co
        uv.data[loop.index].uv = (co.x / (2 * radius) + 0.5, co.y / (2 * radius) + 0.5)
    return g


def critter(scene, location):
    """1 m tall capsule (radius 0.25) standing at location."""
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.25, location=(0, 0, 0), segments=24, ring_count=12)
    c = bpy.context.active_object
    for v in c.data.vertices:  # pull the hemispheres apart -> 1 m capsule
        v.co.z += 0.25 if v.co.z > 0 else -0.25
    c.location = Vector(location) + Vector((0, 0, 0.5))
    m = bpy.data.materials.new("critter")
    m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.9, 0.35, 0.05, 1)
    c.data.materials.append(m)
    bpy.ops.object.shade_smooth()
    return c


def bounds(objs):
    pts = [o.matrix_world @ Vector(c) for o in objs for c in o.bound_box]
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    return lo, hi


def camera_for(scene, lo, hi, fov_deg=35.0, elev_deg=18.0, azim_deg=-35.0):
    cam_data = bpy.data.cameras.new("cam")
    cam_data.angle = math.radians(fov_deg)
    cam_data.clip_end = 5000
    cam = bpy.data.objects.new("cam", cam_data)
    scene.collection.objects.link(cam)
    centre = (lo + hi) / 2
    radius = (hi - lo).length / 2
    dist = radius / math.sin(math.radians(fov_deg) / 2) * 1.02
    e, a = math.radians(elev_deg), math.radians(azim_deg)
    offset = Vector((math.sin(a) * math.cos(e), -math.cos(a) * math.cos(e), math.sin(e))) * dist
    cam.location = centre + offset
    direction = centre - cam.location
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    cam_data.clip_start = max(0.01, dist / 1000)
    scene.camera = cam
    return cam


def render(asset):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    setup_render(scene)
    world(scene)
    bpy.ops.import_scene.gltf(filepath=str(ROOT / asset["file"]))
    model = [o for o in scene.objects if o.type == "MESH"]
    lo, hi = bounds(model)
    h = max(hi.z, 0.01)
    # put the critter beside the model: next to the trunk for trees/mushrooms,
    # otherwise just outside the model's bounding box
    if asset["collision"] == "cylinder" and asset["category"] in ("tree", "mushroom", "stump"):
        cx = asset["collision_radius_m"] + 0.6
    else:
        cx = hi.x + 0.6
    cap = critter(scene, (cx, lo.y if hi.y - lo.y < 4 else 0.0, 0))
    span = max(hi.x - lo.x, hi.y - lo.y, h, 2.0)
    ground(scene, span * 1.6)
    lo2, hi2 = bounds(model + [cap])
    lo2.z = min(lo2.z, 0)
    camera_for(scene, lo2, hi2)
    scene.render.filepath = str(OUT / f"{asset['id']}.png")
    bpy.ops.render.render(write_still=True)
    if h > 12:  # critter's-eye close-up of the base
        r = asset["collision_radius_m"] or 3.0
        blo = Vector((-r - 2, -r - 2, 0))
        bhi = Vector((cx + 1.5, r + 2, min(h, max(6.0, 2.2 * r))))
        for o in list(scene.objects):
            if o.type == "CAMERA":
                bpy.data.objects.remove(o, do_unlink=True)
        camera_for(scene, blo, bhi, fov_deg=50, elev_deg=8, azim_deg=-30)
        scene.render.filepath = str(OUT / f"{asset['id']}_base.png")
        bpy.ops.render.render(write_still=True)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    OUT.mkdir(parents=True, exist_ok=True)
    manifest = json.loads((ROOT / "assets" / "env" / "manifest.json").read_text())
    for a in manifest:
        if argv and a["id"] not in argv:
            continue
        print("[preview]", a["id"], flush=True)
        render(a)


if __name__ == "__main__":
    main()
