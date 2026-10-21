"""Scene / object utilities shared by every Blender-side script.

Coordinate convention used by all builders (Blender space):
    +Y = forward (barrel direction)   -> exported as glTF/Godot -Z
    +Z = up                           -> exported as glTF/Godot +Y
    +X = right                        -> glTF/Godot +X
    1 unit = 1 metre.
"""
from __future__ import annotations

import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Vector

HERE = Path(__file__).resolve().parent            # tools/weapons/blender/bbd
TOOLS = HERE.parent.parent                         # tools/weapons
ROOT = TOOLS.parent.parent                         # repository root
CACHE = ROOT / "tools" / "_cache" / "weapons"
BUILD = CACHE / "build"                            # per-asset bake images + reports
DERIVED = CACHE / "derived"                        # textures derived from scans
OUT_WEAPONS = ROOT / "assets" / "weapons"
OUT_PROPS = ROOT / "assets" / "props"


def script_args() -> list[str]:
    """Arguments after the `--` separator of `blender --python x.py -- ...`."""
    return sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []


def sources_meta() -> dict:
    p = CACHE / "sources_meta.json"
    if not p.exists():
        raise SystemExit("run tools/weapons/fetch_sources.py first")
    return json.loads(p.read_text())


def cache_file(rel: str) -> str:
    return str(CACHE / rel)


def reset_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.unit_settings.system = "METRIC"
    sc.unit_settings.scale_length = 1.0


def link(obj: bpy.types.Object) -> bpy.types.Object:
    bpy.context.scene.collection.objects.link(obj)
    return obj


def new_object(name: str, mesh: bpy.types.Mesh) -> bpy.types.Object:
    return link(bpy.data.objects.new(name, mesh))


def select_only(objs, active=None) -> None:
    for o in bpy.context.view_layer.objects:
        if o is not None:
            o.select_set(False)
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = active or (objs[0] if objs else None)


def apply_modifiers(obj: bpy.types.Object) -> None:
    """Bake the modifier stack into the mesh data (headless-safe, no operators)."""
    if not obj.modifiers:
        return
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(obj.evaluated_get(dg), preserve_all_data_layers=True, depsgraph=dg)
    old = obj.data
    obj.modifiers.clear()
    obj.data = me
    if old.users == 0:
        bpy.data.meshes.remove(old)


def apply_transform(obj: bpy.types.Object) -> None:
    obj.data.transform(obj.matrix_world)
    obj.matrix_world = Matrix.Identity(4)


def place(obj, loc=(0, 0, 0), rot_deg=(0, 0, 0), scale=1.0, apply=True):
    """Position an object (Euler XYZ in degrees) and optionally freeze it."""
    obj.location = Vector(loc)
    obj.rotation_euler = tuple(math.radians(a) for a in rot_deg)
    obj.scale = (scale, scale, scale) if isinstance(scale, (int, float)) else scale
    if apply:
        bpy.context.view_layer.update()
        apply_transform(obj)
    return obj


def duplicate(obj, name=None):
    d = obj.copy()
    d.data = obj.data.copy()
    d.name = name or obj.name + "_dup"
    return link(d)


def join(objs, name=None):
    """Join meshes into the first object (operator needs a selection context)."""
    objs = [o for o in objs if o is not None]
    if len(objs) == 1:
        if name:
            objs[0].name = name
        return objs[0]
    select_only(objs, objs[0])
    with bpy.context.temp_override(active_object=objs[0], selected_editable_objects=objs, selected_objects=objs):
        bpy.ops.object.join()
    if name:
        objs[0].name = name
    return objs[0]


def tri_count(obj) -> int:
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def world_bounds(objs):
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for o in objs:
        if o.type != "MESH":
            continue
        for v in o.data.vertices:
            w = o.matrix_world @ v.co
            lo = Vector(map(min, lo, w))
            hi = Vector(map(max, hi, w))
    return lo, hi


def gltf_vec(v) -> list[float]:
    """Blender (x, y, z) -> glTF/Godot (x, z, -y), rounded for reports."""
    return [round(v[0], 4), round(v[2], 4), round(-v[1], 4)]


def setup_cycles(samples=16, gpu=True):
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.samples = samples
    sc.cycles.use_denoising = False
    if gpu:
        prefs = bpy.context.preferences.addons["cycles"].preferences
        for kind in ("OPTIX", "CUDA"):
            try:
                prefs.compute_device_type = kind
                prefs.refresh_devices()
                devs = [d for d in prefs.devices if d.type == kind]
                if devs:
                    for d in prefs.devices:
                        d.use = d.type == kind
                    sc.cycles.device = "GPU"
                    return kind
            except TypeError:
                continue
    sc.cycles.device = "CPU"
    return "CPU"
