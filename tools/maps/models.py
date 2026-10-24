"""Original models for the Hamster Cage and Toy Box Bash, made in Blender.

    blender --background --factory-startup --python tools/maps/models.py -- [names...]

Each model is a small generator below (`@model("cage/plant")`): primitives,
bevels, booleans, subdivision and smooth shading, joined into one mesh and
exported to assets/maps/<name>.glb (glTF, +Y up, metres, base at y = 0 unless
it says otherwise). Materials carry no textures: each is named "cage:<key>"
and the game draws it with the cage's own material for that key (CageKit.mat:
toy plastic, painted wood, ice...), or "accent", which the game maps to a
colour per instance. So the models match the procedural kits they dress
(CageKit.dress), whose colliders, footprints and loot spots stay as they were.

Also writes assets/credits/maps.json (original work, MIT like the code).
Coordinates below are Blender's (Z up); the exporter turns them into Godot's
(Y up, Blender -Y = Godot +Z, the front of a kit).
"""
from __future__ import annotations

import json
import math
import random
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets" / "maps"
CREDITS = ROOT / "assets" / "credits" / "maps.json"
MODELS: dict = {}

# viewport colours for the material keys (the game uses its own materials)
SWATCH = {
    "plastic_lime": (0.56, 0.86, 0.22), "plastic_pink": (1.0, 0.5, 0.68), "plastic_teal": (0.16, 0.72, 0.74),
    "plastic_purple": (0.58, 0.38, 0.86), "plastic_white": (0.95, 0.95, 0.93), "snow": (0.95, 0.97, 1.0),
    "ice": (0.75, 0.88, 1.0), "frost": (0.9, 0.95, 1.0), "ball_plastic": (0.85, 0.8, 1.0),
    "cardboard_in": (0.55, 0.4, 0.25), "accent": (0.9, 0.3, 0.3),
}


def model(name: str):
    def deco(fn):
        MODELS[name] = fn
        return fn
    return deco


# ---------------------------------------------------------------- helpers

def reset() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)


def mat(key: str):
    """The material slot for a cage material key (or "accent")."""
    name = key if key == "accent" else "cage:" + key
    m = bpy.data.materials.get(name)
    if m is None:
        m = bpy.data.materials.new(name)
        c = SWATCH.get(key, (0.8, 0.8, 0.8))
        m.diffuse_color = (*c, 1.0)
    return m


def link(ob):
    bpy.context.scene.collection.objects.link(ob)
    return ob


def activate(ob):
    for o in bpy.context.scene.objects:
        o.select_set(False)
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)


def assign(ob, key: str):
    ob.data.materials.clear()
    ob.data.materials.append(mat(key))
    return ob


def apply_mods(ob):
    activate(ob)
    for m in list(ob.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)
    return ob


def bevel(ob, width: float, segments: int = 3, angle: float = 40.0):
    m = ob.modifiers.new("Bevel", "BEVEL")
    m.width = width
    m.segments = segments
    m.limit_method = "ANGLE"
    m.angle_limit = math.radians(angle)
    m.harden_normals = False
    return apply_mods(ob)


def subsurf(ob, levels: int = 2):
    m = ob.modifiers.new("Subsurf", "SUBSURF")
    m.levels = levels
    m.render_levels = levels
    return apply_mods(ob)


def smooth(ob, angle: float = 35.0):
    me = ob.data
    for p in me.polygons:
        p.use_smooth = True
    me.set_sharp_from_angle(angle=math.radians(angle))
    return ob


def cube(size, at=(0, 0, 0), key="accent", name="cube"):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=at)
    ob = bpy.context.active_object
    ob.name = name
    ob.scale = size
    bpy.ops.object.transform_apply(scale=True)
    return assign(ob, key)


def cylinder(r, depth, at=(0, 0, 0), key="accent", verts=32, rot=(0, 0, 0), name="cyl"):
    bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=depth, vertices=verts, location=at, rotation=rot)
    ob = bpy.context.active_object
    ob.name = name
    return assign(ob, key)


def sphere(r, at=(0, 0, 0), key="accent", segs=32, rings=16, scale=(1, 1, 1), name="sphere"):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r, segments=segs, ring_count=rings, location=at)
    ob = bpy.context.active_object
    ob.name = name
    ob.scale = scale
    bpy.ops.object.transform_apply(scale=True)
    return assign(ob, key)


def ico(r, at=(0, 0, 0), key="accent", subdiv=3, name="ico"):
    bpy.ops.mesh.primitive_ico_sphere_add(radius=r, subdivisions=subdiv, location=at)
    ob = bpy.context.active_object
    ob.name = name
    return assign(ob, key)


def cut(ob, cutter):
    """Boolean difference; the cutter is removed."""
    m = ob.modifiers.new("Cut", "BOOLEAN")
    m.operation = "DIFFERENCE"
    m.solver = "EXACT"
    m.material_mode = "TRANSFER"   # the cut faces take the cutter's material
    m.object = cutter
    apply_mods(ob)
    bpy.data.objects.remove(cutter, do_unlink=True)
    return ob


def displace(ob, strength: float, scale: float, seed: int = 0):
    tex = bpy.data.textures.new(f"noise{seed}", "CLOUDS")
    tex.noise_scale = scale
    tex.noise_depth = 2
    m = ob.modifiers.new("Displace", "DISPLACE")
    m.texture = tex
    m.strength = strength
    m.mid_level = 0.5
    m.texture_coords = "OBJECT"
    empty = bpy.data.objects.new(f"noise_origin{seed}", None)
    link(empty)
    empty.location = (seed * 3.17, seed * 1.31, seed * 2.03)
    m.texture_coords_object = empty
    apply_mods(ob)
    bpy.data.objects.remove(empty, do_unlink=True)
    return ob


def mesh_object(name: str, verts, faces, key: str):
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in verts], [], faces)
    me.update()
    ob = link(bpy.data.objects.new(name, me))
    return assign(ob, key)


def join(objs):
    activate(objs[0])
    for o in objs[1:]:
        o.select_set(True)
    bpy.ops.object.join()
    return bpy.context.active_object


def export(name: str, objs) -> Path:
    ob = join(objs) if len(objs) > 1 else objs[0]
    ob.name = name.split("/")[-1]
    activate(ob)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    out = OUT / f"{name}.glb"
    out.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=str(out), export_format="GLB", use_selection=True, export_apply=True,
                              export_yup=True, export_materials="EXPORT", export_normals=True,
                              export_texcoords=True, export_tangents=False)
    tris = sum(len(p.vertices) - 2 for p in ob.data.polygons)
    print(f"[maps] {name}: {tris} tris, {out.stat().st_size / 1024:.0f} KB")
    return out


# ---------------------------------------------------------------- the Hamster Cage

@model("cage/plant")
def cage_plant():
    """Plastic aquarium plant: seven tapered, twisting leaves on a little base
    (MultiMesh ground cover in the lagoon, ~6 m tall)."""
    rnd = random.Random(7)
    parts = []
    for i in range(7):
        a = math.tau * i / 7 + rnd.random()
        base = Vector((math.cos(a), math.sin(a), 0)) * rnd.uniform(0.0, 0.7)
        h = rnd.uniform(3.6, 6.3)
        lean = Vector((math.cos(a), math.sin(a), 0)) * rnd.uniform(0.4, 1.5)
        key = "plastic_lime" if i % 3 else ("plastic_pink" if i % 2 == 0 else "plastic_teal")
        verts, faces = [], []
        n = 12
        for s in range(n + 1):
            t = s / n
            centre = base + Vector((0, 0, h * t)) + lean * t * t \
                + Vector((math.sin(t * 6.0 + a), math.cos(t * 6.0 + a), 0)) * 0.22
            w = 0.42 * (1.0 - t * 0.85) * (0.6 + 0.4 * math.sin(math.pi * min(t * 1.6, 1.0)))
            twist = a + t * 2.2
            side = Vector((math.cos(twist), math.sin(twist), 0))
            verts += [centre - side * w, centre + side * w]
            if s:
                k = 2 * s
                faces.append((k - 2, k - 1, k + 1, k))
        leaf = mesh_object(f"leaf{i}", verts, faces, key)
        sol = leaf.modifiers.new("Solid", "SOLIDIFY")
        sol.thickness = 0.07
        sol.offset = 0.0
        apply_mods(leaf)
        subsurf(leaf, 1)
        smooth(leaf, 60)
        parts.append(leaf)
    stem = cylinder(0.35, 0.3, (0, 0, 0.15), "plastic_teal", 20)
    bevel(stem, 0.06, 2)
    smooth(stem)
    parts.append(stem)
    return parts


@model("cage/snowball")
def cage_snowball():
    """A clump of four soft snowballs (~1.6 m), lumpy but smooth."""
    rnd = random.Random(3)
    parts = []
    for i in range(4):
        a = math.tau * i / 4 + rnd.random()
        d = rnd.uniform(0.1, 0.85)
        r = rnd.uniform(0.75, 1.05)
        b = ico(r, (math.cos(a) * d, math.sin(a) * d, r * rnd.uniform(0.45, 0.65)), "snow", 4)
        b.scale = (1.0, 1.0, rnd.uniform(0.62, 0.8))
        activate(b)
        bpy.ops.object.transform_apply(scale=True)
        displace(b, 0.18, 0.55, i + 1)
        smooth(b, 80)
        parts.append(b)
    return parts


@model("cage/chew_block")
def cage_chew_block():
    """A painted chew block, 1 m (scaled in game): rounded edges, a chewing
    hole in each side and gnawed corners. Paint = "accent"."""
    blk = cube((1.0, 1.0, 1.0), (0, 0, 0.5), "accent", "block")
    for k in range(4):
        a = k * math.pi / 2
        hole = cylinder(0.17, 0.5, (math.cos(a) * 0.5, math.sin(a) * 0.5, 0.5), "cardboard_in", 24,
                        (math.pi / 2, 0, a + math.pi / 2))
        cut(blk, hole)
    for corner in [(0.5, 0.5, 1.0), (-0.5, -0.5, 1.0)]:
        nib = sphere(0.16, corner, "cardboard_in", 16, 8)
        cut(blk, nib)
    bevel(blk, 0.045, 3)
    smooth(blk, 40)
    return [blk]


@model("cage/hamster_ball")
def cage_hamster_ball():
    """A clear exercise ball, radius 1 (scaled in game), resting on its base:
    a lid ring with a grip, a band round the middle and rows of air slots."""
    centre = Vector((0, 0, 0.95))
    shell = sphere(1.0, centre, "ball_plastic", 64, 32)
    for z, n in [(-0.35, 14), (0.2, 16)]:
        for i in range(n):
            a = math.tau * (i + 0.5 * (z > 0)) / n
            ring_r = math.sqrt(max(0.0, 1.0 - z * z))
            at = centre + Vector((math.cos(a) * ring_r, math.sin(a) * ring_r, z))
            slot = cube((0.3, 0.07, 0.26), at, "ball_plastic", "slot")
            slot.rotation_euler = (0, 0, a)
            activate(slot)
            bpy.ops.object.transform_apply(rotation=True)
            cut(shell, slot)
    sol = shell.modifiers.new("Solid", "SOLIDIFY")
    sol.thickness = 0.025
    apply_mods(shell)
    smooth(shell, 50)
    # the screw lid and its grip, on top
    lid = cylinder(0.55, 0.12, centre + Vector((0, 0, 0.86)), "plastic_purple", 48)
    bevel(lid, 0.03, 3)
    smooth(lid)
    grip = cylinder(0.2, 0.1, centre + Vector((0, 0, 0.96)), "plastic_purple", 32)
    bevel(grip, 0.025, 2)
    smooth(grip)
    bpy.ops.mesh.primitive_torus_add(major_radius=1.005, minor_radius=0.035, location=centre,
                                     major_segments=72, minor_segments=10)
    band = assign(bpy.context.active_object, "plastic_purple")
    smooth(band, 80)
    return [shell, lid, grip, band]


@model("cage/ice_cube")
def cage_ice_cube():
    """An ice cube, 1 m (scaled in game): softly rounded, a frosted top."""
    ice = cube((1.0, 1.0, 1.0), (0, 0, 0.48), "ice", "ice")
    bevel(ice, 0.09, 4)
    smooth(ice, 40)
    frost = cube((0.9, 0.9, 0.04), (0, 0, 0.985), "frost", "frost")
    displace(frost, 0.03, 0.2, 5)
    bevel(frost, 0.015, 2)
    smooth(frost, 60)
    return [ice, frost]


# ---------------------------------------------------------------- main

def write_credits(names: list[str] | None = None) -> None:
    files = sorted(str(p.relative_to(ROOT)) for p in OUT.rglob("*.glb"))
    entry = {
        "asset": "Hamster Cage and Toy Box Bash models",
        "author": "Bunny Beat Down project",
        "author_url": "",
        "source_url": "",
        "license": "MIT (project)",
        "license_url": "https://opensource.org/license/mit",
        "changes": "Original models made in Blender by tools/maps/models.py",
        "used_for": "The Hamster Cage and Toy Box Bash: props, toys and landmarks",
        "files": files,
    }
    CREDITS.write_text(json.dumps([entry], indent=1) + "\n")


def main() -> None:
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    wanted = [n for n in MODELS if not argv or n in argv or n.split("/")[0] in argv]
    failed = []
    for name in wanted:
        reset()
        try:
            export(name, MODELS[name]())
        except Exception as e:  # keep going, report at the end
            import traceback
            traceback.print_exc()
            failed.append((name, str(e)))
    write_credits(wanted)
    for f in failed:
        print("[maps] FAILED", *f)
    if failed:
        sys.exit(1)


if __name__ == "__main__":
    main()
