"""Generator for the walk-through hollow log (imported by process_models.py, runs in Blender).

No suitable downloadable CC0/CC-BY hollow log (open at both ends, textured,
game-sized) was found on Poly Haven or Sketchfab, so this one is modelled
procedurally and dressed with real Poly Haven photo-scanned PBR textures (CC0):
mossy brown bark outside (bark_brown_02), weathered wood inside (rough_wood).

Shape: a slightly bent, lumpy tube lying along X with an inner bore wide enough
for a 1 m critter, jagged broken ends (rims marked sharp), seam-free cylindrical
UVs in metres so the textures keep real-world texel density.
"""
from __future__ import annotations

import json
import math
import random
import subprocess
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector, noise

TOOLS = Path(__file__).resolve().parent
CACHE = TOOLS.parents[0] / "_cache" / "env"


def _material(name: str, tex_dir: Path, work: Path) -> bpy.types.Material:
    """Principled material from a Poly Haven texture folder (albedo/normal/rough/ao)."""
    orm = work / f"{name}_orm_src.jpg"
    job = [{"dst": str(orm), "mode": "orm", "rough_src": str(tex_dir / "roughness.jpg"),
            "ao_src": str(tex_dir / "ao.jpg"), "max": 2048, "quality": 92}]
    jf = work / f"{name}_orm_job.json"
    jf.write_text(json.dumps(job))
    subprocess.run(["python3", "-I", str(TOOLS / "texconv.py"), str(jf)], check=True, stdout=subprocess.DEVNULL)

    m = bpy.data.materials.new(name)
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    col = nt.nodes.new("ShaderNodeTexImage")
    col.image = bpy.data.images.load(str(tex_dir / "albedo.jpg"))
    nt.links.new(col.outputs["Color"], b.inputs["Base Color"])
    nrm = nt.nodes.new("ShaderNodeTexImage")
    nrm.image = bpy.data.images.load(str(tex_dir / "normal.png"))
    nrm.image.colorspace_settings.name = "Non-Color"
    nmap = nt.nodes.new("ShaderNodeNormalMap")
    nt.links.new(nrm.outputs["Color"], nmap.inputs["Color"])
    nt.links.new(nmap.outputs["Normal"], b.inputs["Normal"])
    ormn = nt.nodes.new("ShaderNodeTexImage")
    ormn.image = bpy.data.images.load(str(orm))
    ormn.image.colorspace_settings.name = "Non-Color"
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    nt.links.new(ormn.outputs["Color"], sep.inputs["Color"])
    nt.links.new(sep.outputs["Green"], b.inputs["Roughness"])
    nt.links.new(sep.outputs["Blue"], b.inputs["Metallic"])
    return m


def build(cfg: dict, work: Path):
    work.mkdir(parents=True, exist_ok=True)
    L = float(cfg.get("length_m", 14.0))     # log length
    R = float(cfg.get("radius_m", 2.1))      # outer radius
    wall = float(cfg.get("wall_m", 0.38))    # wall thickness -> bore ~1.7 m radius
    na, nl = int(cfg.get("segments_around", 64)), int(cfg.get("segments_along", 56))
    rng = random.Random(int(cfg.get("seed", 3)))
    off = Vector((rng.uniform(0, 100), rng.uniform(0, 100), rng.uniform(0, 100)))

    def n3(theta, x, ring_scale, along_scale, shift=0.0):
        p = Vector((math.cos(theta) * ring_scale, math.sin(theta) * ring_scale, x * along_scale + shift))
        return noise.noise(p + off)  # sampled on a circle -> periodic in theta

    def jag(theta, end):
        """How far the broken end tears back into the log (m), spiky like splintered wood."""
        p = Vector((math.cos(theta) * 1.6, math.sin(theta) * 1.6, 37.0 * end)) + off
        broad = noise.noise(p) * 0.5 + 0.5
        spikes = abs(noise.noise(p * 4.5))
        return 0.1 + 1.1 * broad ** 2 + 0.55 * spikes ** 2

    def centre(x):
        return Vector((0.0, 0.35 * math.sin(x * 0.21 + 0.5), 0.22 * math.sin(x * 0.29)))

    def radius(theta, x, inner):
        r = R * (1.0 + 0.06 * n3(theta, x, 1.1, 0.16) + 0.022 * n3(theta, x, 4.0, 0.8, 5.0))
        if inner:
            r -= wall * (1.0 + 0.3 * n3(theta, x, 2.2, 0.45, 11.0))
        return r

    verts, faces, face_mat, face_uv = [], [], [], []
    ring_x = {}

    def shell(inner: bool):
        start = len(verts)
        tile = 2.5 if inner else 3.0
        for i in range(nl + 1):
            u = i / nl
            for j in range(na):
                th = 2 * math.pi * j / na
                x0, x1 = -L / 2 + jag(th, 0), L / 2 - jag(th, 1)
                x = x0 + (x1 - x0) * u
                r = radius(th, x, inner)
                c = centre(x)
                verts.append(Vector((x, c.y + r * math.cos(th), c.z + r * math.sin(th) * 0.93)))
                ring_x[(inner, i, j)] = x
        circ = 2 * math.pi * (R - (wall if inner else 0.0))
        for i in range(nl):
            for j in range(na):
                corners = [(i, j), (i, j + 1), (i + 1, j + 1), (i + 1, j)]
                if inner:
                    corners = corners[::-1]
                faces.append([start + ci * na + (cj % na) for ci, cj in corners])
                face_mat.append(1 if inner else 0)
                face_uv.append([(cj / na * circ / tile, ring_x[(inner, ci, cj % na)] / tile) for ci, cj in corners])
        return start

    outer, inner = shell(False), shell(True)
    rim_faces = []
    for end, i in ((0, 0), (1, nl)):
        for j in range(na):
            a, b = outer + i * na + j, outer + i * na + (j + 1) % na
            c, d = inner + i * na + (j + 1) % na, inner + i * na + j
            quad = [a, b, c, d] if end == 1 else [a, d, c, b]
            rim_faces.append(len(faces))
            faces.append(quad)
            face_mat.append(1)
            face_uv.append([(verts[k].y / 1.5, verts[k].z / 1.5) for k in quad])

    me = bpy.data.meshes.new("log_hollow")
    me.from_pydata([tuple(v) for v in verts], [], faces)
    me.update()
    uv = me.uv_layers.new(name="UVMap")
    for f, uvs in zip(me.polygons, face_uv):
        f.material_index = face_mat[f.index]
        f.use_smooth = True
        for li, coord in zip(f.loop_indices, uvs):
            uv.data[li].uv = coord
    # sharp edges where the broken rims meet the bark / bore
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.faces.ensure_lookup_table()
    rim = set(rim_faces)
    for e in bm.edges:
        linked = [f.index in rim for f in e.link_faces]
        if len(linked) == 2 and linked[0] != linked[1]:
            e.smooth = False
    bm.to_mesh(me)
    bm.free()

    me.materials.append(_material("log_bark", CACHE / "ph_bark_brown_02", work))
    me.materials.append(_material("log_wood", CACHE / "ph_rough_wood", work))
    obj = bpy.data.objects.new("log_hollow", me)
    bpy.context.scene.collection.objects.link(obj)
    return obj


SOURCES = {  # credited texture sources (Poly Haven ids) used by this generator
    "textures": ["bark_brown_02", "rough_wood"],
}
