"""Rebuild the cage and toy kits' own geometry as clean models, in Blender.

    godot --headless --path . -s tests/export_kits.gd          # -> tools/_cache/maps/raw/<id>.glb
    blender --background --factory-startup --python tools/maps/refine.py -- [ids or "cage"/"toy"...]
    godot --headless --import                                   # (the game sees new models after an import)

The raw kit is the procedural one (boxes, lathes, rings, ellipsoids, built
face by face), so its shapes, doorways and floors match the colliders the
game still builds from the same code. Here every piece is welded shut, its
hard edges bevelled (a soft highlight on every edge, as on a moulded toy or
a sanded block), curved surfaces smoothed, and closed all-curved parts
(domes, balls, buds) subdivided so their silhouettes round off. Material
names ("cage:<key>", "accent...") and UVs carry through, and the result goes
to assets/maps/<id>.glb, where CageKit.made_as() finds it.
"""
from __future__ import annotations

import math
import sys
from pathlib import Path

import bmesh
import bpy

sys.path.insert(0, str(Path(__file__).resolve().parent))
import models  # noqa: E402  (the shared helpers and the credits writer)

ROOT = models.ROOT
RAW = ROOT / "tools" / "_cache" / "maps" / "raw"

# bevel width (m) per model; edges sharper than BEVEL_ANGLE get it
BEVEL = {"default": 0.07, "cage/chew_sticks": 0.05, "cage/bridge": 0.06, "cage/water_bottle": 0.04,
         "cage/castle": 0.12, "cage/hut": 0.06, "cage/gym": 0.06,
         "toy/letter_block": 0.05, "toy/track": 0.03, "toy/baseplate": 0.02, "toy/dollhouse": 0.08,
         "cage/room": 3.0, "cage/fridge": 2.5, "cage/tank_trim": 0.5, "cage/icicles": 0.06,
         "toy/bedroom": 1.0, "toy/mobile": 0.4, "cage/plane_body": 0.05, "cage/plane_propeller": 0.04}


def bevel_width(rel: str) -> float:
    """The width for a model, or for its family ("toy/letter_block_3" -> "toy/letter_block")."""
    if rel in BEVEL:
        return BEVEL[rel]
    family = rel.rstrip("0123456789").rstrip("_")
    return BEVEL.get(family, BEVEL["default"])
BEVEL_ANGLE = 50.0
SMOOTH_ANGLE = 50.0


def import_raw(path: Path):
    models.reset()
    bpy.ops.import_scene.gltf(filepath=str(path))
    objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    for m in bpy.data.materials:   # (Godot's glTF export writes "cage:key" as "cage_key")
        if m.name.startswith("cage_"):
            m.name = "cage:" + m.name[len("cage_"):]
    for o in objs:
        models.activate(o)
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return models.join(objs) if len(objs) > 1 else objs[0]


def weld(ob) -> None:
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.002)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(ob.data)
    bm.free()


def round_off_curved_parts(ob) -> int:
    """Subdivide (Catmull-Clark, one level) each closed loose part whose every
    edge is gentler than SMOOTH_ANGLE: ellipsoids, domes, buds. Returns how many."""
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bm.edges.ensure_lookup_table()
    seen = set()
    rounded = []
    for f0 in bm.faces:
        if f0.index in seen:
            continue
        part, stack = [], [f0]
        seen.add(f0.index)
        while stack:
            f = stack.pop()
            part.append(f)
            for e in f.edges:
                for g in e.link_faces:
                    if g.index not in seen:
                        seen.add(g.index)
                        stack.append(g)
        edges = {e for f in part for e in f.edges}
        closed = all(len(e.link_faces) == 2 for e in edges)
        gentle = all(e.calc_face_angle(0.0) < math.radians(SMOOTH_ANGLE) for e in edges)
        if closed and gentle and len(part) >= 12:
            rounded.append(part)
    for part in rounded:
        edges = list({e for f in part for e in f.edges})
        bmesh.ops.subdivide_edges(bm, edges=edges, cuts=1, use_grid_fill=True, smooth=1.0)
    bm.to_mesh(ob.data)
    bm.free()
    return len(rounded)


def refine(rel: str) -> None:
    ob = import_raw(RAW / f"{rel}.glb")
    weld(ob)
    rounded = round_off_curved_parts(ob)
    m = ob.modifiers.new("Bevel", "BEVEL")
    m.width = bevel_width(rel)
    m.segments = 3
    m.limit_method = "ANGLE"
    m.angle_limit = math.radians(BEVEL_ANGLE)
    m.use_clamp_overlap = True
    m.harden_normals = True
    models.apply_mods(ob)
    models.smooth(ob, SMOOTH_ANGLE)
    wn = ob.modifiers.new("Normals", "WEIGHTED_NORMAL")
    wn.keep_sharp = True
    models.apply_mods(ob)
    print(f"[refine] {rel}: rounded {rounded} curved parts")
    models.export(rel, [ob])


def main() -> None:
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    rels = sorted(str(p.relative_to(RAW))[:-4] for p in RAW.rglob("*.glb"))
    wanted = [r for r in rels if not argv or r in argv or r.split("/")[0] in argv]
    failed = []
    for rel in wanted:
        try:
            refine(rel)
        except Exception as e:  # keep going, report at the end
            import traceback
            traceback.print_exc()
            failed.append((rel, str(e)))
    models.write_credits()
    for f in failed:
        print("[refine] FAILED", *f)
    if failed:
        sys.exit(1)


if __name__ == "__main__":
    main()
