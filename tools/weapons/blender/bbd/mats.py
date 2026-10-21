"""Source materials for the bake pipeline.

Each material here is a *bake source*: a single Principled BSDF whose inputs are
driven by Poly Haven CC0 textures, the unwrapped photoscan strips and Cycles-only
helpers (Bevel-node edge wear, AO cavity dirt). bake.py renders those inputs into
one 1024 px atlas per asset, so none of these node graphs have to survive glTF
export — only the baked result ships.

Rules every material follows (bake.py relies on them):
  * exactly one Principled BSDF called "BSDF" wired to the Material Output
  * colours are given in sRGB hex and converted to linear here
  * mat["bbd_sources"] lists the third-party sources it samples (for credits)
"""
from __future__ import annotations

import json
import math

import bpy

from .util import DERIVED, cache_file, sources_meta

_META = None


def meta():
    global _META
    if _META is None:
        _META = sources_meta()
    return _META


def srgb(hexstr, a=1.0):
    """'#rrggbb' (sRGB) -> linear RGBA tuple for node sockets."""
    h = hexstr.lstrip("#")
    out = []
    for i in range(3):
        c = int(h[2 * i:2 * i + 2], 16) / 255.0
        out.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    return (*out, a)


# --------------------------------------------------------------------------- node helper

class NB:
    """Tiny node-graph helper that keeps graphs readable."""

    def __init__(self, mat):
        self.mat = mat
        self.nt = mat.node_tree
        self.n = self.nt.nodes
        self.l = self.nt.links
        self.x = -300

    def add(self, kind, **props):
        node = self.n.new(kind)
        node.location = (self.x, 0)
        self.x -= 40
        for k, v in props.items():
            if k.startswith("in_"):
                node.inputs[k[3:].replace("_", " ")].default_value = v
            else:
                setattr(node, k, v)
        return node

    def link(self, a, b):
        self.l.new(a, b)
        return b

    # ---- common building blocks
    def coords(self, kind="Object", scale=1.0, rot=(0, 0, 0), loc=(0, 0, 0), uv="src"):
        if kind == "UV":
            tc = self.add("ShaderNodeUVMap", uv_map=uv)
            out = tc.outputs["UV"]
        else:
            tc = self.add("ShaderNodeTexCoord")
            out = tc.outputs[kind]
        mp = self.add("ShaderNodeMapping")
        mp.inputs["Scale"].default_value = (scale, scale, scale) if not isinstance(scale, tuple) else scale
        mp.inputs["Rotation"].default_value = tuple(math.radians(a) for a in rot)
        mp.inputs["Location"].default_value = loc
        self.link(out, mp.inputs["Vector"])
        return mp.outputs["Vector"]

    def image(self, path, vec, colorspace="sRGB", box=False, blend=0.3, extension="REPEAT"):
        node = self.add("ShaderNodeTexImage")
        img = bpy.data.images.load(path, check_existing=True)
        img.colorspace_settings.name = colorspace
        node.image = img
        node.extension = extension
        if box:
            node.projection = "BOX"
            node.projection_blend = blend
        self.link(vec, node.inputs["Vector"])
        return node

    def math(self, op, a, b=None, clamp=False):
        m = self.add("ShaderNodeMath", operation=op, use_clamp=clamp)
        for i, v in enumerate((a, b)):
            if v is None:
                continue
            if isinstance(v, (int, float)):
                m.inputs[i].default_value = v
            else:
                self.link(v, m.inputs[i])
        return m.outputs[0]

    def mix(self, fac, a, b, blend="MIX", data="RGBA", clamp=True):
        m = self.add("ShaderNodeMix", data_type=data, blend_type=blend, clamp_result=clamp)
        ins = {"RGBA": (6, 7), "FLOAT": (2, 3)}[data]
        outs = {"RGBA": 2, "FLOAT": 0}[data]
        for sock, v in ((m.inputs[0], fac), (m.inputs[ins[0]], a), (m.inputs[ins[1]], b)):
            if isinstance(v, (int, float, tuple)):
                sock.default_value = v
            else:
                self.link(v, sock)
        return m.outputs[outs]

    def ramp(self, fac, stops):
        r = self.add("ShaderNodeValToRGB")
        cr = r.color_ramp
        while len(cr.elements) > 1:
            cr.elements.remove(cr.elements[-1])
        cr.elements[0].position = stops[0][0]
        cr.elements[0].color = stops[0][1]
        for pos, col in stops[1:]:
            e = cr.elements.new(pos)
            e.color = col
        self.link(fac, r.inputs["Fac"])
        return r.outputs["Color"]

    def noise(self, vec=None, scale=5.0, detail=4.0, rough=0.55, dim=None):
        nz = self.add("ShaderNodeTexNoise", noise_dimensions=dim or "3D")
        nz.inputs["Scale"].default_value = scale
        nz.inputs["Detail"].default_value = detail
        nz.inputs["Roughness"].default_value = rough
        if vec is not None:
            self.link(vec, nz.inputs["Vector"])
        return nz

    def bw(self, color):
        n = self.add("ShaderNodeRGBToBW")
        self.link(color, n.inputs["Color"])
        return n.outputs["Val"]

    def edge_mask(self, radius=0.003, gain=4.0, samples=8):
        """1 on convex/concave edges, 0 on flat areas (Cycles Bevel node)."""
        bev = self.add("ShaderNodeBevel", samples=samples)
        bev.inputs["Radius"].default_value = radius
        geo = self.add("ShaderNodeNewGeometry")
        dot = self.add("ShaderNodeVectorMath", operation="DOT_PRODUCT")
        self.link(bev.outputs["Normal"], dot.inputs[0])
        self.link(geo.outputs["Normal"], dot.inputs[1])
        inv = self.math("SUBTRACT", 1.0, dot.outputs["Value"])
        return self.math("MULTIPLY", inv, gain, clamp=True)

    def cavity(self, distance=0.01, samples=16):
        ao = self.add("ShaderNodeAmbientOcclusion", samples=samples, only_local=True)
        ao.inputs["Distance"].default_value = distance
        return ao.outputs["AO"]

    def normal_map(self, color, strength=1.0, uv="src"):
        nm = self.add("ShaderNodeNormalMap", space="TANGENT", uv_map=uv)
        nm.inputs["Strength"].default_value = strength
        self.link(color, nm.inputs["Color"])
        return nm.outputs["Normal"]

    def bump(self, height, strength=0.3, distance=0.002, normal=None):
        b = self.add("ShaderNodeBump")
        b.inputs["Strength"].default_value = strength
        b.inputs["Distance"].default_value = distance
        self.link(height, b.inputs["Height"])
        if normal is not None:
            self.link(normal, b.inputs["Normal"])
        return b.outputs["Normal"]

    def set(self, bsdf_input, value):
        sock = self.bsdf.inputs[bsdf_input]
        if isinstance(value, (int, float, tuple)):
            sock.default_value = value
        else:
            self.link(value, sock)


def _new(name, sources=()):
    """Get-or-create a material; returns (mat, NB) or (mat, None) if cached."""
    if name in bpy.data.materials:
        return bpy.data.materials[name], None
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nb = NB(mat)
    nb.bsdf = mat.node_tree.nodes["Principled BSDF"]
    nb.bsdf.name = "BSDF"
    mat["bbd_sources"] = ",".join(sources)
    return mat, nb


def _ph(asset_id, m):
    return cache_file(meta()[asset_id]["files"][m])


def _tile(asset_id):
    """Real-world tile size (m) of a Poly Haven texture."""
    d = meta()[asset_id].get("real_size_mm") or [1000, 1000]
    return max(d[0], 1.0) / 1000.0


# --------------------------------------------------------------------------- wood / fibre

def wood(name, ph="dark_wood", tint="#ffffff", coords="box", rot=(0, 0, 0), density=1.0,
         rough=None, wear=0.35, dirt=0.4, bump=0.25):
    """Varnished / weathered wood. coords='src' uses the builder's planar UVs."""
    mat, nb = _new(name, (ph,))
    if nb is None:
        return mat
    s = density / _tile(ph)
    if coords == "box":
        vec = nb.coords("Object", s, rot)
        dif = nb.image(_ph(ph, "Diffuse"), vec, box=True)
        rgh = nb.image(_ph(ph, "Rough"), vec, "Non-Color", box=True)
        nrm = None
    else:
        vec = nb.coords("UV", s, rot)
        dif = nb.image(_ph(ph, "Diffuse"), vec)
        rgh = nb.image(_ph(ph, "Rough"), vec, "Non-Color")
        nrm = nb.image(_ph(ph, "nor_gl"), vec, "Non-Color")
    col = nb.mix(1.0, dif.outputs["Color"], srgb(tint), blend="MULTIPLY")
    edge = nb.edge_mask(0.004, 3.0)
    col = nb.mix(nb.math("MULTIPLY", edge, wear), col, nb.mix(1.0, col, (1.35, 1.25, 1.1, 1), "MULTIPLY"))
    cav = nb.cavity(0.012)
    col = nb.mix(nb.math("MULTIPLY", nb.math("SUBTRACT", 1.0, cav), dirt), col, srgb("#2a1e14"))
    nb.set("Base Color", col)
    r = rgh.outputs["Color"]
    if rough is not None:
        r = nb.mix(0.6, r, (rough, rough, rough, 1))
    nb.set("Roughness", nb.bw(r))
    height = nb.bw(dif.outputs["Color"])
    n_in = nb.normal_map(nrm.outputs["Color"], 0.8) if nrm else None
    nb.set("Normal", nb.bump(height, bump, 0.002, n_in))
    return mat


def fibre(name, ph="hessian_380", tint="#c9a46a", coords="src", density=1.0, ply=3, twist=40.0,
          rough=0.85):
    """Twine / jute rope: hessian texture + helical ply grooves along src UV.

    For sweeps the src UV is (u around 0..1, v metres along), so a wave texture
    on (u*ply + v*twist) produces the twisted-ply look.
    """
    mat, nb = _new(name, (ph,))
    if nb is None:
        return mat
    if coords == "src":
        uv = nb.add("ShaderNodeUVMap", uv_map="src").outputs["UV"]
        sep = nb.add("ShaderNodeSeparateXYZ")
        nb.link(uv, sep.inputs[0])
        helix = nb.math("ADD", nb.math("MULTIPLY", sep.outputs["X"], float(ply)),
                        nb.math("MULTIPLY", sep.outputs["Y"], twist))
        wave = nb.math("SINE", nb.math("MULTIPLY", helix, 2 * math.pi))
        ply_h = nb.math("MULTIPLY", nb.math("ADD", wave, 1.0), 0.5)
        vec = nb.coords("UV", density / _tile(ph) * 0.35)
    else:
        ply_h = None
        vec = nb.coords("Object", density / _tile(ph))
    dif = nb.image(_ph(ph, "Diffuse"), vec, box=(coords != "src"))
    rgh = nb.image(_ph(ph, "Rough"), vec, "Non-Color", box=(coords != "src"))
    col = nb.mix(0.75, dif.outputs["Color"], srgb(tint), blend="MULTIPLY")
    col = nb.mix(0.35, col, srgb(tint), blend="MIX")
    if ply_h is not None:
        col = nb.mix(nb.math("MULTIPLY", nb.math("SUBTRACT", 1.0, ply_h), 0.45), col, srgb("#4a3826"))
        height = nb.math("ADD", ply_h, nb.math("MULTIPLY", nb.bw(dif.outputs["Color"]), 0.3))
        nb.set("Normal", nb.bump(height, 0.6, 0.0015))
    else:
        nb.set("Normal", nb.bump(nb.bw(dif.outputs["Color"]), 0.5, 0.002))
    nb.set("Base Color", col)
    nb.set("Roughness", nb.mix(0.5, nb.bw(rgh.outputs["Color"]), rough, data="FLOAT"))
    nb.set("Sheen Weight", 0.3)
    return mat


def leather(name, tint="#8a5a34", density=1.0, rough=0.55):
    mat, nb = _new(name, ("brown_leather",))
    if nb is None:
        return mat
    vec = nb.coords("Object", density / _tile("brown_leather"))
    dif = nb.image(_ph("brown_leather", "Diffuse"), vec, box=True)
    rgh = nb.image(_ph("brown_leather", "Rough"), vec, "Non-Color", box=True)
    col = nb.mix(0.55, dif.outputs["Color"], srgb(tint), blend="MULTIPLY")
    edge = nb.edge_mask(0.003, 3.0)
    col = nb.mix(nb.math("MULTIPLY", edge, 0.4), col, srgb("#b98a5c"))
    nb.set("Base Color", col)
    nb.set("Roughness", nb.mix(0.5, nb.bw(rgh.outputs["Color"]), rough, data="FLOAT"))
    nb.set("Normal", nb.bump(nb.bw(dif.outputs["Color"]), 0.35, 0.002))
    return mat


def burlap(name, tint="#b89a6a", density=1.6):
    mat, nb = _new(name, ("hessian_380",))
    if nb is None:
        return mat
    vec = nb.coords("Object", density / _tile("hessian_380"))
    dif = nb.image(_ph("hessian_380", "Diffuse"), vec, box=True)
    col = nb.mix(0.6, dif.outputs["Color"], srgb(tint), blend="MULTIPLY")
    cav = nb.cavity(0.02)
    col = nb.mix(nb.math("MULTIPLY", nb.math("SUBTRACT", 1.0, cav), 0.5), col, srgb("#3b2a1a"))
    nb.set("Base Color", col)
    nb.set("Roughness", 0.9)
    nb.set("Sheen Weight", 0.4)
    nb.set("Normal", nb.bump(nb.bw(dif.outputs["Color"]), 0.7, 0.002))
    return mat


def bark(name, tint="#ffffff", density=3.0):
    """Pine bark plates (scaled up so the plates read at critter scale)."""
    mat, nb = _new(name, ("pine_bark",))
    if nb is None:
        return mat
    vec = nb.coords("Object", density / _tile("pine_bark"))
    dif = nb.image(_ph("pine_bark", "Diffuse"), vec, box=True)
    rgh = nb.image(_ph("pine_bark", "Rough"), vec, "Non-Color", box=True)
    col = nb.mix(1.0, dif.outputs["Color"], srgb(tint), blend="MULTIPLY")
    edge = nb.edge_mask(0.004, 3.0)
    col = nb.mix(nb.math("MULTIPLY", edge, 0.35), col, srgb("#c08a5a"))
    nb.set("Base Color", col)
    nb.set("Roughness", nb.bw(rgh.outputs["Color"]))
    nb.set("Normal", nb.bump(nb.bw(dif.outputs["Color"]), 0.8, 0.004))
    return mat


# --------------------------------------------------------------------------- metals / paint

METALS = {
    #           colour (sRGB)  roughness  tex influence
    "steel":   ("#8c9096", 0.30, 0.6),
    "blued":   ("#363d47", 0.28, 0.7),
    "iron":    ("#5d5a57", 0.48, 0.7),
    "brass":   ("#b48f52", 0.26, 0.6),
    "copper":  ("#c7825a", 0.30, 0.6),
    "galv":    ("#a7aaab", 0.40, 0.6),
    "gold":    ("#c79a45", 0.22, 0.55),
}


def metal(name, kind="steel", density=1.0, wear=0.5, tint=None, rough=None):
    """Bare metal (steel, blued, iron, brass, copper, galvanised) with scuffs."""
    mat, nb = _new(name, ("metal_plate_02",))
    if nb is None:
        return mat
    base_hex, r0, k = METALS[kind]
    vec = nb.coords("Object", density * 12.0 / _tile("metal_plate_02"))
    dif = nb.image(_ph("metal_plate_02", "Diffuse"), vec, box=True)
    rgh = nb.image(_ph("metal_plate_02", "Rough"), vec, "Non-Color", box=True)
    lum = nb.bw(dif.outputs["Color"])
    # brighten the texture's luminance variation around 1.0 and tint it
    var = nb.math("ADD", nb.math("MULTIPLY", lum, 1.6 * k), 1.0 - 0.35 * k)
    col = nb.mix(1.0, srgb(tint or base_hex), nb.math("MINIMUM", var, 1.4), blend="MULTIPLY")
    edge = nb.edge_mask(0.003, 3.5)
    col = nb.mix(nb.math("MULTIPLY", edge, wear), col, nb.mix(1.0, col, (1.25, 1.25, 1.25, 1), "MULTIPLY"))
    cav = nb.cavity(0.01)
    col = nb.mix(nb.math("MULTIPLY", nb.math("SUBTRACT", 1.0, cav), 0.6), col, srgb("#2b2621"))
    nb.set("Base Color", col)
    nb.set("Metallic", nb.math("SUBTRACT", 1.0, nb.math("MULTIPLY", nb.math("SUBTRACT", 1.0, cav), 0.5)))
    rr = nb.mix(k, rough if rough is not None else r0, nb.bw(rgh.outputs["Color"]), data="FLOAT")
    rr = nb.math("SUBTRACT", rr, nb.math("MULTIPLY", edge, 0.12 * wear))
    nb.set("Roughness", rr)
    nb.set("Normal", nb.bump(lum, 0.12, 0.001))
    return mat


def paint(name, color="#e8741c", under="steel", density=1.0, chip=0.6, rough=0.42, ph="green_metal_rust",
          stencil=None, stencil_hex="#efe3c6", st_center=(0.0, 0.0), st_size=0.1, st_plane="YZ", st_rotate=True):
    """Chipped enamel paint over metal (edges and noise reveal the metal).

    stencil: optional mask PNG sprayed on in `stencil_hex`, projected in node
    space onto `st_plane` around st_center; st_rotate lays the image's vertical
    axis along the plane's first axis (a carrot pointing forward along +Y).
    """
    mat, nb = _new(name, (ph, "metal_plate_02"))
    if nb is None:
        return mat
    vec = nb.coords("Object", density * 2.0 / _tile(ph))
    dif = nb.image(_ph(ph, "Diffuse"), vec, box=True)
    rgh = nb.image(_ph(ph, "Rough"), vec, "Non-Color", box=True)
    lum = nb.bw(dif.outputs["Color"])
    # paint = colour modulated by the photo's brightness variation (keeps grime/strokes)
    var = nb.math("ADD", nb.math("MULTIPLY", lum, 2.4), 0.35)
    pcol = nb.mix(1.0, srgb(color), nb.math("MINIMUM", var, 1.3), blend="MULTIPLY")
    # large soft grime blotches so big painted panels never read as flat plastic
    grime = nb.noise(nb.coords("Object", 1.0), scale=9.0, detail=3.0, rough=0.5)
    pcol = nb.mix(nb.math("MULTIPLY", nb.math("SUBTRACT", grime.outputs["Fac"], 0.35), 0.8, clamp=True), pcol,
                  nb.mix(1.0, pcol, srgb("#6a5a44"), blend="MULTIPLY"))
    if stencil:
        tc = nb.add("ShaderNodeTexCoord").outputs["Object"]
        sp = nb.add("ShaderNodeSeparateXYZ")
        nb.link(tc, sp.inputs[0])
        a_ax, b_ax = st_plane[0], st_plane[1]
        da = nb.math("DIVIDE", nb.math("SUBTRACT", sp.outputs[a_ax], st_center[0]), st_size)
        db = nb.math("DIVIDE", nb.math("SUBTRACT", sp.outputs[b_ax], st_center[1]), st_size)
        comb = nb.add("ShaderNodeCombineXYZ")
        if st_rotate:   # image v runs along +a (tip forward), image u along b
            nb.link(nb.math("ADD", db, 0.5), comb.inputs[0])
            nb.link(nb.math("ADD", da, 0.5), comb.inputs[1])
        else:
            nb.link(nb.math("ADD", da, 0.5), comb.inputs[0])
            nb.link(nb.math("ADD", db, 0.5), comb.inputs[1])
        st = nb.image(stencil, comb.outputs[0], "Non-Color", extension="CLIP")
        spray = nb.noise(nb.coords("Object", 1.0), scale=300.0, detail=2.0)
        cover = nb.math("MULTIPLY", st.outputs["Color"], nb.math("ADD", 0.6, nb.math("MULTIPLY", spray.outputs["Fac"], 0.6)), clamp=True)
        pcol = nb.mix(cover, pcol, nb.mix(1.0, srgb(stencil_hex), nb.math("MINIMUM", var, 1.1), blend="MULTIPLY"))
    edge = nb.edge_mask(0.004, 4.0)
    nz = nb.noise(nb.coords("Object", 1.0), scale=60.0, detail=6.0, rough=0.65)
    scr = nb.noise(nb.coords("Object", (6.0, 60.0, 6.0)), scale=14.0, detail=2.0)
    chipm = nb.math("GREATER_THAN", nb.math("ADD", nb.math("ADD", nb.math("MULTIPLY", edge, chip),
                                                             nb.math("MULTIPLY", nz.outputs["Fac"], 0.55)),
                                            nb.math("MULTIPLY", nb.math("SUBTRACT", scr.outputs["Fac"], 0.5), 0.5)), 0.74)
    mcol = srgb(METALS[under][0])
    col = nb.mix(chipm, pcol, mcol)
    cav = nb.cavity(0.012)
    col = nb.mix(nb.math("MULTIPLY", nb.math("SUBTRACT", 1.0, cav), 0.5), col, srgb("#2a2018"))
    nb.set("Base Color", col)
    nb.set("Metallic", chipm)
    pr = nb.mix(0.5, rough, nb.bw(rgh.outputs["Color"]), data="FLOAT")
    nb.set("Roughness", nb.mix(chipm, pr, 0.3, data="FLOAT"))
    nb.set("Normal", nb.bump(nb.math("SUBTRACT", lum, nb.math("MULTIPLY", chipm, 0.4)), 0.25, 0.0015))
    return mat


def plain(name, color, rough=0.5, metallic=0.0, coat=0.0, noise_amt=0.08, noise_scale=40.0, bump=0.1,
          sheen=0.0):
    """Simple procedural material (rubber, cork, seeds, glass-ish) with subtle variation."""
    mat, nb = _new(name)
    if nb is None:
        return mat
    nz = nb.noise(nb.coords("Object", 1.0), scale=noise_scale, detail=5.0)
    col = nb.mix(noise_amt, srgb(color), nz.outputs["Color"], blend="OVERLAY")
    cav = nb.cavity(0.01)
    col = nb.mix(nb.math("MULTIPLY", nb.math("SUBTRACT", 1.0, cav), 0.4), col, srgb("#1d1712"))
    nb.set("Base Color", col)
    nb.set("Roughness", nb.math("ADD", rough, nb.math("MULTIPLY", nb.math("SUBTRACT", nz.outputs["Fac"], 0.5), 0.15)))
    nb.set("Metallic", metallic)
    if coat:
        nb.set("Coat Weight", coat)
    if sheen:
        nb.set("Sheen Weight", sheen)
    if bump:
        nb.set("Normal", nb.bump(nz.outputs["Fac"], bump, 0.001))
    return mat


# --------------------------------------------------------------------------- carrots

def _strip(name):
    p = DERIVED / f"{name}.png"
    return str(p) if p.exists() else None


def carrot_skin(name="carrot_skin", tint="#ffffff", rough=0.48, v_range=(0.17, 0.98), u_repeat=1.0,
                normal_strength=1.0):
    """Photoscanned carrot skin strip on the builder's src UV (u around, v crown->tip)."""
    mat, nb = _new(name, ("carrot_scan",))
    if nb is None:
        return mat
    alb, nrm = _strip("carrot_skin_albedo"), _strip("carrot_skin_normal")
    uv = nb.add("ShaderNodeUVMap", uv_map="src").outputs["UV"]
    mp = nb.add("ShaderNodeMapping")
    mp.inputs["Scale"].default_value = (u_repeat, v_range[1] - v_range[0], 1.0)
    mp.inputs["Location"].default_value = (0.0, v_range[0], 0.0)
    nb.link(uv, mp.inputs["Vector"])
    vec = mp.outputs["Vector"]
    if alb:
        a = nb.image(alb, vec, extension="EXTEND")
        col = nb.mix(1.0, a.outputs["Color"], srgb(tint), blend="MULTIPLY")
        lum = nb.bw(a.outputs["Color"])
    else:  # fallback before prep_scans has run
        col = srgb("#e06a18")
        lum = nb.noise(scale=30.0).outputs["Fac"]
    nb.set("Base Color", col)
    nb.set("Roughness", nb.math("ADD", rough, nb.math("MULTIPLY", nb.math("SUBTRACT", 0.5, lum), 0.4)))
    nb.set("Subsurface Weight", 0.0)
    if nrm:
        n = nb.image(nrm, vec, "Non-Color", extension="EXTEND")
        nb.set("Normal", nb.normal_map(n.outputs["Color"], normal_strength))
    return mat


def carrot_flesh(name="carrot_flesh"):
    """Cut carrot face: pale core, xylem ring, deep-orange cortex.

    Driven by the disk UVs that geo.lathe() writes on its caps (centre 0.5,0.5,
    rim at radius 0.5), so it works on any cap regardless of object space.
    """
    mat, nb = _new(name)
    if nb is None:
        return mat
    uv = nb.add("ShaderNodeUVMap", uv_map="src").outputs["UV"]
    sep = nb.add("ShaderNodeSeparateXYZ")
    nb.link(uv, sep.inputs[0])
    dx = nb.math("SUBTRACT", sep.outputs["X"], 0.5)
    dy = nb.math("SUBTRACT", sep.outputs["Y"], 0.5)
    rn = nb.math("MULTIPLY", nb.math("SQRT", nb.math("ADD", nb.math("POWER", dx, 2.0), nb.math("POWER", dy, 2.0))), 2.0)
    ang = nb.math("ARCTAN2", dx, dy)
    streak = nb.noise(None, scale=3.0)
    comb = nb.add("ShaderNodeCombineXYZ")
    nb.link(nb.math("MULTIPLY", ang, 6.0), comb.inputs[0])
    nb.link(nb.math("MULTIPLY", rn, 1.5), comb.inputs[1])
    nb.link(comb.outputs[0], streak.inputs["Vector"])
    rn2 = nb.math("ADD", rn, nb.math("MULTIPLY", nb.math("SUBTRACT", streak.outputs["Fac"], 0.5), 0.12))
    col = nb.ramp(rn2, [
        (0.00, srgb("#f0a03a")), (0.30, srgb("#f5ad42")), (0.42, srgb("#fbc463")),
        (0.50, srgb("#e8801f")), (0.85, srgb("#e2701a")), (0.96, srgb("#c4561a")), (1.0, srgb("#a8481a"))])
    nb.set("Base Color", col)
    nb.set("Roughness", 0.32)
    nb.set("Normal", nb.bump(streak.outputs["Fac"], 0.15, 0.001))
    return mat


def leaf(name="carrot_leaf", color="#4f8a2b", vein="#9cc56a", rough=0.45):
    """Carrot greens / clover: midrib along src-v, colour variation, glossy cuticle."""
    mat, nb = _new(name)
    if nb is None:
        return mat
    uv = nb.add("ShaderNodeUVMap", uv_map="src").outputs["UV"]
    sep = nb.add("ShaderNodeSeparateXYZ")
    nb.link(uv, sep.inputs[0])
    mid = nb.math("ABSOLUTE", nb.math("SUBTRACT", sep.outputs["Y"], 0.5))
    rib = nb.math("SUBTRACT", 1.0, nb.math("MULTIPLY", mid, 22.0), clamp=True)
    nz = nb.noise(nb.coords("Object", 1.0), scale=90.0, detail=3.0)
    base = nb.mix(0.25, srgb(color), nz.outputs["Color"], blend="OVERLAY")
    base = nb.mix(nb.math("MULTIPLY", sep.outputs["X"], 0.35), base, srgb("#2f5e1b"))
    col = nb.mix(nb.math("MULTIPLY", rib, 0.7), base, srgb(vein))
    nb.set("Base Color", col)
    nb.set("Roughness", rough)
    nb.set("Sheen Weight", 0.2)
    nb.set("Normal", nb.bump(nb.math("SUBTRACT", 1.0, rib), 0.3, 0.0008))
    return mat


# --------------------------------------------------------------------------- acorn

def _acorn_meta():
    p = DERIVED / "acorn_strip.json"
    return json.loads(p.read_text()) if p.exists() else {"v_rim": 0.42, "v_cap_top": 0.05, "v_tip": 0.97}


def acorn(name, part="cap", tint="#ffffff", u_repeat=1.0, v_range=None, rough=None, normal_strength=1.0,
          pale_band=0.0):
    """Photoscanned acorn strip: part='cap' (scaly cupule) or 'shell' (glossy nut).

    The builder's src UV is (u around, v 0..1 over the part); v is remapped into
    the matching band of the unwrapped scan strip.
    """
    mat, nb = _new(name, ("acorn_scan",))
    if nb is None:
        return mat
    am = _acorn_meta()
    if v_range is None:
        v_range = (am["v_cap_top"], am["v_rim"] - 0.01) if part == "cap" else (am.get("v_nut", am["v_rim"] + 0.04),
                                                                             am.get("v_nut", am["v_rim"] + 0.04) + 0.22)
    alb, nrm, rgh = _strip("acorn_strip_albedo"), _strip("acorn_strip_normal"), _strip("acorn_strip_rough")
    uv = nb.add("ShaderNodeUVMap", uv_map="src").outputs["UV"]
    mp = nb.add("ShaderNodeMapping")
    mp.inputs["Scale"].default_value = (u_repeat, v_range[1] - v_range[0], 1.0)
    mp.inputs["Location"].default_value = (0.0, v_range[0], 0.0)
    nb.link(uv, mp.inputs["Vector"])
    vec = mp.outputs["Vector"]
    if alb:
        a = nb.image(alb, vec, extension="EXTEND")
        col = nb.mix(1.0, a.outputs["Color"], srgb(tint), blend="MULTIPLY")
    else:
        col = srgb("#7a4a22" if part == "shell" else "#a08060")
    if part == "shell":
        # deepen + add the faint longitudinal striations of a real acorn shell
        stri = nb.noise(None, scale=1.0)
        comb = nb.add("ShaderNodeCombineXYZ")
        sep = nb.add("ShaderNodeSeparateXYZ")
        nb.link(uv, sep.inputs[0])
        nb.link(nb.math("MULTIPLY", sep.outputs["X"], 60.0), comb.inputs[0])
        nb.link(nb.math("MULTIPLY", sep.outputs["Y"], 3.0), comb.inputs[1])
        nb.link(comb.outputs[0], stri.inputs["Vector"])
        col = nb.mix(0.18, col, stri.outputs["Color"], blend="OVERLAY")
        if pale_band > 0:
            # real acorns have a paler, matte collar just below the cupule (v = 0 here)
            band = nb.math("SUBTRACT", 1.0, nb.math("DIVIDE", sep.outputs["Y"], pale_band), clamp=True)
            band = nb.math("MULTIPLY", nb.math("POWER", band, 1.5), 0.75)
            col = nb.mix(band, col, srgb("#b89064"))
    nb.set("Base Color", col)
    if rgh and rough is None:
        r = nb.image(rgh, vec, "Non-Color", extension="EXTEND")
        nb.set("Roughness", nb.bw(r.outputs["Color"]))
    else:
        nb.set("Roughness", rough if rough is not None else (0.22 if part == "shell" else 0.75))
    if part == "shell":
        nb.set("Coat Weight", 0.6)
        nb.set("Coat Roughness", 0.12)
    if nrm:
        n = nb.image(nrm, vec, "Non-Color", extension="EXTEND")
        nb.set("Normal", nb.normal_map(n.outputs["Color"], normal_strength))
    return mat


# --------------------------------------------------------------------------- decals

def stencil_wood(name, stencil_png, ph="rough_wood", tint="#ffffff", paint_hex="#e8741c", proj="XZ",
                 center=(0, 0), size=0.5, density=1.0, wear=0.35):
    """Weathered wood with a sprayed stencil (carrot logo) projected along one axis."""
    mat, nb = _new(name, (ph,))
    if nb is None:
        return mat
    s = density / _tile(ph)
    vec = nb.coords("Object", s)
    dif = nb.image(_ph(ph, "Diffuse"), vec, box=True)
    rgh = nb.image(_ph(ph, "Rough"), vec, "Non-Color", box=True)
    col = nb.mix(1.0, dif.outputs["Color"], srgb(tint), blend="MULTIPLY")
    # stencil projection: object coords in the chosen plane -> 0..1
    tc = nb.add("ShaderNodeTexCoord").outputs["Object"]
    sep = nb.add("ShaderNodeSeparateXYZ")
    nb.link(tc, sep.inputs[0])
    a, b = {"XZ": ("X", "Z"), "YZ": ("Y", "Z"), "XY": ("X", "Y")}[proj]
    comb = nb.add("ShaderNodeCombineXYZ")
    nb.link(nb.math("ADD", nb.math("DIVIDE", nb.math("SUBTRACT", sep.outputs[a], center[0]), size), 0.5), comb.inputs[0])
    nb.link(nb.math("ADD", nb.math("DIVIDE", nb.math("SUBTRACT", sep.outputs[b], center[1]), size), 0.5), comb.inputs[1])
    st = nb.image(stencil_png, comb.outputs[0], "Non-Color", extension="CLIP")
    nz = nb.noise(nb.coords("Object", 1.0), scale=25.0, detail=6.0)
    # worn spray paint: stencil alpha * grain-dependent coverage
    cover = nb.math("MULTIPLY", st.outputs["Color"], nb.math("ADD", nb.math("MULTIPLY", nz.outputs["Fac"], 0.8), 0.45), clamp=True)
    cover = nb.math("MULTIPLY", cover, nb.math("ADD", nb.math("MULTIPLY", nb.bw(dif.outputs["Color"]), 0.9), 0.5), clamp=True)
    col = nb.mix(cover, col, nb.mix(1.0, srgb(paint_hex), dif.outputs["Color"], blend="OVERLAY"))
    edge = nb.edge_mask(0.004, 3.0)
    col = nb.mix(nb.math("MULTIPLY", edge, wear), col, nb.mix(1.0, col, (1.3, 1.25, 1.15, 1), "MULTIPLY"))
    cav = nb.cavity(0.02)
    col = nb.mix(nb.math("MULTIPLY", nb.math("SUBTRACT", 1.0, cav), 0.6), col, srgb("#231a12"))
    nb.set("Base Color", col)
    nb.set("Roughness", nb.mix(cover, nb.bw(rgh.outputs["Color"]), 0.55, data="FLOAT"))
    nb.set("Normal", nb.bump(nb.bw(dif.outputs["Color"]), 0.45, 0.003))
    return mat


# --------------------------------------------------------------------------- unbaked (exported as-is)

def alpha_card(name, png, color_hex="#ffffff", rough=0.7, sheen=0.5, cutoff=0.4, normal_png=None,
               normal_strength=1.0, emission=0.0, sources=()):
    """Two-sided alpha-tested material exported directly (glTF alphaMode MASK, doubleSided).

    Not baked: used where the texture carries the silhouette (pappus bristles,
    leaf / petal / flower canopies). The Math 'GREATER_THAN' on alpha is how the
    glTF exporter recognises alpha clipping. Optional tangent normal map (on the
    object's single UV map) and a little emission for glowing fluff.
    """
    if name in bpy.data.materials:
        return bpy.data.materials[name]
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.name = "BSDF"
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(png, check_existing=True)
    tex.image.alpha_mode = "STRAIGHT"
    mixc = nt.nodes.new("ShaderNodeMix")
    mixc.data_type = "RGBA"
    mixc.blend_type = "MULTIPLY"
    mixc.inputs[0].default_value = 1.0
    nt.links.new(tex.outputs["Color"], mixc.inputs[6])
    mixc.inputs[7].default_value = srgb(color_hex)
    nt.links.new(mixc.outputs[2], bsdf.inputs["Base Color"])
    gt = nt.nodes.new("ShaderNodeMath")
    gt.operation = "GREATER_THAN"
    gt.inputs[1].default_value = cutoff
    nt.links.new(tex.outputs["Alpha"], gt.inputs[0])
    nt.links.new(gt.outputs[0], bsdf.inputs["Alpha"])
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Sheen Weight"].default_value = sheen
    if normal_png:
        nt_img = nt.nodes.new("ShaderNodeTexImage")
        nt_img.image = bpy.data.images.load(normal_png, check_existing=True)
        nt_img.image.colorspace_settings.name = "Non-Color"
        nm = nt.nodes.new("ShaderNodeNormalMap")
        nm.inputs["Strength"].default_value = normal_strength
        nt.links.new(nt_img.outputs["Color"], nm.inputs["Color"])
        nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    if emission:
        nt.links.new(mixc.outputs[2], bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = emission
    mat.surface_render_method = "DITHERED"
    mat.use_backface_culling = False
    mat["bbd_sources"] = ",".join(sources)
    mat["bbd_nobake"] = True
    return mat


def derived(name):
    """Path of a texture derived from a scan by prep_scans.py."""
    return str(DERIVED / name)


def gilded(name, density=1.0, bole="#6e2a19"):
    """Gold leaf over carved oak: polished gold, grain showing through, red bole in the recesses."""
    mat, nb = _new(name, ("oak_veneer_01",))
    if nb is None:
        return mat
    vec = nb.coords("Object", density / _tile("oak_veneer_01"))
    dif = nb.image(_ph("oak_veneer_01", "Diffuse"), vec, box=True)
    lum = nb.bw(dif.outputs["Color"])
    gold = nb.mix(1.0, srgb(METALS["gold"][0]), nb.math("ADD", 0.75, nb.math("MULTIPLY", lum, 0.6)), blend="MULTIPLY")
    cav = nb.cavity(0.012)
    edge = nb.edge_mask(0.003, 3.0)
    worn = nb.math("MULTIPLY", nb.math("SUBTRACT", 1.0, cav), 1.6, clamp=True)
    col = nb.mix(worn, gold, srgb(bole))
    col = nb.mix(nb.math("MULTIPLY", edge, 0.5), col, nb.mix(1.0, col, (1.3, 1.25, 1.1, 1), "MULTIPLY"))
    nb.set("Base Color", col)
    nb.set("Metallic", nb.math("SUBTRACT", 1.0, nb.math("MULTIPLY", worn, 0.8)))
    nb.set("Roughness", nb.math("ADD", 0.18, nb.math("MULTIPLY", nb.math("ADD", worn, nb.math("MULTIPLY", lum, 0.3)), 0.3)))
    nb.set("Normal", nb.bump(lum, 0.35, 0.002))
    return mat


def emboss_scales(name, color_hex="#c79a45", cell=0.034, metal=1.0, recess="#5b3a14"):
    """Embossed acorn-cupule scales (imbricate rows) on src UV in metres - for gilded lids."""
    mat, nb = _new(name)
    if nb is None:
        return mat
    uv = nb.add("ShaderNodeUVMap", uv_map="src").outputs["UV"]
    sep = nb.add("ShaderNodeSeparateXYZ")
    nb.link(uv, sep.inputs[0])
    row = nb.math("FLOOR", nb.math("DIVIDE", sep.outputs["Y"], cell * 0.75))
    shift = nb.math("MULTIPLY", nb.math("MODULO", row, 2.0), 0.5)
    fu = nb.math("SUBTRACT", nb.math("FRACT", nb.math("ADD", nb.math("DIVIDE", sep.outputs["X"], cell), shift)), 0.5)
    fv = nb.math("FRACT", nb.math("DIVIDE", sep.outputs["Y"], cell * 0.75))
    # shield-shaped scale: rounded at the bottom (fv = 0), tucked under the row above
    d = nb.math("SQRT", nb.math("ADD", nb.math("POWER", nb.math("MULTIPLY", fu, 2.0), 2.0),
                                 nb.math("POWER", nb.math("MULTIPLY", nb.math("SUBTRACT", fv, 0.15), 1.5), 2.0)))
    h = nb.math("SUBTRACT", 1.0, d, clamp=True)
    h = nb.math("POWER", h, 0.6)
    col = nb.mix(nb.math("SUBTRACT", 1.0, nb.math("MULTIPLY", h, 3.0), clamp=True), srgb(color_hex), srgb(recess))
    nz = nb.noise(nb.coords("Object", 1.0), scale=120.0, detail=3.0)
    col = nb.mix(0.15, col, nz.outputs["Color"], blend="OVERLAY")
    nb.set("Base Color", col)
    nb.set("Metallic", nb.math("MULTIPLY", metal, nb.math("ADD", 0.3, nb.math("MULTIPLY", h, 2.0), clamp=True)))
    nb.set("Roughness", nb.math("SUBTRACT", 0.42, nb.math("MULTIPLY", h, 0.22)))
    nb.set("Normal", nb.bump(h, 0.8, 0.004))
    return mat


def velvet(name="velvet", color="#7d1622"):
    return plain(name, color, rough=0.75, noise_amt=0.12, noise_scale=220.0, bump=0.05, sheen=1.0)


def gills(name="gills", color="#efe4cf", n=180):
    """Mushroom gills on a lathe's src UV (u around): fine radial lamellae with shadowed gaps."""
    mat, nb = _new(name)
    if nb is None:
        return mat
    uv = nb.add("ShaderNodeUVMap", uv_map="src").outputs["UV"]
    sep = nb.add("ShaderNodeSeparateXYZ")
    nb.link(uv, sep.inputs[0])
    w = nb.math("ABSOLUTE", nb.math("SINE", nb.math("MULTIPLY", sep.outputs["X"], math.pi * n)))
    lam = nb.math("POWER", w, 0.35)
    col = nb.mix(nb.math("SUBTRACT", 1.0, lam), srgb(color), srgb("#8a7558"))
    nb.set("Base Color", col)
    nb.set("Roughness", 0.8)
    nb.set("Sheen Weight", 0.3)
    nb.set("Normal", nb.bump(lam, 0.7, 0.01))
    return mat


def stipe(name="stipe", base="#e9dcc3", band="#7a5a3a"):
    """Parasol-mushroom stem: cream with brown snake-skin zigzag bands."""
    mat, nb = _new(name)
    if nb is None:
        return mat
    tc = nb.coords("Object", (1.0, 1.0, 1.0))
    nz = nb.noise(tc, scale=14.0, detail=4.0)
    sep = nb.add("ShaderNodeSeparateXYZ")
    nb.link(tc, sep.inputs[0])
    zig = nb.math("SINE", nb.math("ADD", nb.math("MULTIPLY", sep.outputs["Z"], 70.0),
                                  nb.math("MULTIPLY", nz.outputs["Fac"], 6.0)))
    m = nb.math("GREATER_THAN", zig, 0.55)
    col = nb.mix(nb.math("MULTIPLY", m, 0.85), srgb(base), srgb(band))
    nb.set("Base Color", col)
    nb.set("Roughness", 0.7)
    nb.set("Normal", nb.bump(nb.math("ADD", m, nz.outputs["Fac"]), 0.3, 0.004))
    return mat


def planar_image(name, png, sources=(), rough=0.6, tint="#ffffff", normal_png=None, normal_strength=1.0):
    """Baked material sampling an image on the builder's src UV (planar-projected surfaces)."""
    mat, nb = _new(name, sources)
    if nb is None:
        return mat
    uv = nb.add("ShaderNodeUVMap", uv_map="src").outputs["UV"]
    t = nb.image(png, uv, extension="EXTEND")
    nb.set("Base Color", nb.mix(1.0, t.outputs["Color"], srgb(tint), blend="MULTIPLY"))
    nb.set("Roughness", rough)
    if normal_png:
        n = nb.image(normal_png, uv, "Non-Color", extension="EXTEND")
        nb.set("Normal", nb.normal_map(n.outputs["Color"], normal_strength))
    return mat

def twine_wrap(name="twine_wrap", pitch=0.0034, tint="#c8a266", plies=48.0):
    """Tightly coiled jute twine for wrap sleeves (lathe src UV: u around, v metres).

    The coil is a helix with one turn per `pitch` metres; each coil gets a rounded
    height profile (bump) and dark grooves, plus diagonal ply twist inside the strand.
    """
    mat, nb = _new(name, ("hessian_380",))
    if nb is None:
        return mat
    uv = nb.add("ShaderNodeUVMap", uv_map="src").outputs["UV"]
    sep = nb.add("ShaderNodeSeparateXYZ")
    nb.link(uv, sep.inputs[0])
    phase = nb.math("ADD", nb.math("DIVIDE", sep.outputs["Y"], pitch), sep.outputs["X"])
    coil = nb.math("FRACT", phase)
    prof = nb.math("POWER", nb.math("SINE", nb.math("MULTIPLY", coil, math.pi)), 0.5)
    ply = nb.math("SINE", nb.math("MULTIPLY", nb.math("ADD", nb.math("MULTIPLY", coil, 2.0),
                                                          nb.math("MULTIPLY", sep.outputs["X"], plies)), 2 * math.pi))
    ply01 = nb.math("MULTIPLY", nb.math("ADD", ply, 1.0), 0.5)
    vec = nb.coords("UV", 1.0 / _tile("hessian_380") * 2.0)
    dif = nb.image(_ph("hessian_380", "Diffuse"), vec)
    col = nb.mix(0.55, srgb(tint), dif.outputs["Color"], blend="OVERLAY")
    col = nb.mix(nb.math("MULTIPLY", ply01, 0.25), col, srgb("#8a6a3e"))
    col = nb.mix(nb.math("SUBTRACT", 1.0, prof), col, srgb("#3a2a18"))
    nb.set("Base Color", col)
    nb.set("Roughness", 0.88)
    nb.set("Sheen Weight", 0.35)
    height = nb.math("ADD", prof, nb.math("MULTIPLY", ply01, 0.15))
    nb.set("Normal", nb.bump(height, 0.9, 0.0012))
    return mat


def acorn_scale(name="acorn_scale", rows=8, v_range=None, tint="#ffffff"):
    """Cupule scales: scan colours per scale + darker bases / paler fuzzy tips.

    Scale vertices carry src UV (u = azimuth, v = (row + local_v) / rows), so the
    local position inside each scale is fract(v * rows).
    """
    mat, nb = _new(name, ("acorn_scan",))
    if nb is None:
        return mat
    am = _acorn_meta()
    v_range = v_range or (am["v_cap_top"] + 0.02, am["v_rim"] - 0.02)
    uv = nb.add("ShaderNodeUVMap", uv_map="src").outputs["UV"]
    sep = nb.add("ShaderNodeSeparateXYZ")
    nb.link(uv, sep.inputs[0])
    local = nb.math("FRACT", nb.math("MULTIPLY", sep.outputs["Y"], float(rows)))
    mp = nb.add("ShaderNodeMapping")
    mp.inputs["Scale"].default_value = (1.0, v_range[1] - v_range[0], 1.0)
    mp.inputs["Location"].default_value = (0.0, v_range[0], 0.0)
    nb.link(uv, mp.inputs["Vector"])
    alb = _strip("acorn_strip_albedo")
    if alb:
        a = nb.image(alb, mp.outputs["Vector"], extension="EXTEND")
        col = nb.mix(1.0, a.outputs["Color"], srgb(tint), blend="MULTIPLY")
    else:
        col = srgb("#8d7556")
    grad = nb.math("ADD", 0.55, nb.math("MULTIPLY", nb.math("POWER", local, 0.8), 0.7))
    col = nb.mix(1.0, col, grad, blend="MULTIPLY")
    fuzz = nb.noise(nb.coords("Object", 1.0), scale=400.0, detail=2.0)
    col = nb.mix(nb.math("MULTIPLY", nb.math("POWER", local, 3.0), 0.35), col,
                 nb.mix(0.5, srgb("#c9b48f"), fuzz.outputs["Color"], blend="OVERLAY"))
    nb.set("Base Color", col)
    nb.set("Roughness", nb.math("ADD", 0.62, nb.math("MULTIPLY", local, 0.2)))
    nb.set("Sheen Weight", 0.25)
    nb.set("Normal", nb.bump(nb.math("ADD", nb.math("MULTIPLY", local, 0.5), nb.math("MULTIPLY", fuzz.outputs["Fac"], 0.3)),
                             0.35, 0.002))
    return mat


def clover_leaf(name="clover_leaf", color="#3e7a2a", mark="#b3d39a"):
    """White-clover leaflet: deep green with the pale chevron 'watermark' and faint veins.

    Leaflet src UV: u from the base (0) to the notched tip (1), v across (0.5 = midrib).
    """
    mat, nb = _new(name)
    if nb is None:
        return mat
    uv = nb.add("ShaderNodeUVMap", uv_map="src").outputs["UV"]
    sep = nb.add("ShaderNodeSeparateXYZ")
    nb.link(uv, sep.inputs[0])
    x = sep.outputs["X"]
    y = nb.math("ABSOLUTE", nb.math("SUBTRACT", sep.outputs["Y"], 0.5))
    chev = nb.math("ABSOLUTE", nb.math("SUBTRACT", x, nb.math("ADD", 0.30, nb.math("MULTIPLY", y, 0.75))))
    chev = nb.math("SUBTRACT", 1.0, nb.math("MULTIPLY", chev, 9.0), clamp=True)
    rib = nb.math("SUBTRACT", 1.0, nb.math("MULTIPLY", y, 30.0), clamp=True)
    veins = nb.math("POWER", nb.math("ABSOLUTE", nb.math("SINE", nb.math("MULTIPLY", nb.math("DIVIDE", y, nb.math("ADD", x, 0.15)), 18.0))), 12.0)
    nz = nb.noise(nb.coords("Object", 1.0), scale=60.0, detail=3.0)
    col = nb.mix(0.2, srgb(color), nz.outputs["Color"], blend="OVERLAY")
    col = nb.mix(nb.math("MULTIPLY", chev, 0.8), col, srgb(mark))
    col = nb.mix(nb.math("MULTIPLY", nb.math("ADD", rib, nb.math("MULTIPLY", veins, 0.4)), 0.35), col, srgb("#6fa04e"))
    nb.set("Base Color", col)
    nb.set("Roughness", 0.42)
    nb.set("Sheen Weight", 0.25)
    nb.set("Normal", nb.bump(nb.math("ADD", rib, nb.math("MULTIPLY", veins, 0.5)), 0.25, 0.0008))
    return mat


def fabric(name, ph, density=1.0, tint="#ffffff", rough=0.8, gores=0, bands=0.0, seam_hex="#3a2c22"):
    """Real fabric scan (Poly Haven) with optional stitched seams on lathe src UVs.

    gores   number of vertical panels around (seam where frac(u * gores) ~ 0)
    bands   horizontal panel height in metres along the src v (arc length)
    """
    mat, nb = _new(name, (ph,))
    if nb is None:
        return mat
    vec = nb.coords("Object", density / _tile(ph))
    dif = nb.image(_ph(ph, "Diffuse"), vec, box=True, blend=0.4)
    rgh = nb.image(_ph(ph, "Rough"), vec, "Non-Color", box=True, blend=0.4)
    col = nb.mix(1.0, dif.outputs["Color"], srgb(tint), blend="MULTIPLY")
    seam = None
    if gores or bands:
        uv = nb.add("ShaderNodeUVMap", uv_map="src").outputs["UV"]
        sep = nb.add("ShaderNodeSeparateXYZ")
        nb.link(uv, sep.inputs[0])
        parts_ = []
        if gores:
            g = nb.math("FRACT", nb.math("MULTIPLY", sep.outputs["X"], float(gores)))
            parts_.append(nb.math("MINIMUM", g, nb.math("SUBTRACT", 1.0, g)))
        if bands:
            b = nb.math("FRACT", nb.math("DIVIDE", sep.outputs["Y"], bands))
            parts_.append(nb.math("MULTIPLY", nb.math("MINIMUM", b, nb.math("SUBTRACT", 1.0, b)), 0.12))
        d = parts_[0] if len(parts_) == 1 else nb.math("MINIMUM", parts_[0], parts_[1])
        seam = nb.math("SUBTRACT", 1.0, nb.math("MULTIPLY", d, 90.0), clamp=True)
        stitch = nb.math("GREATER_THAN", nb.math("SINE", nb.math("MULTIPLY", nb.math("ADD", sep.outputs["X"], sep.outputs["Y"]), 900.0)), 0.2)
        col = nb.mix(nb.math("MULTIPLY", seam, 0.55), col, srgb(seam_hex))
        col = nb.mix(nb.math("MULTIPLY", nb.math("MULTIPLY", seam, stitch), 0.35), col, srgb("#efe6d0"))
    cav = nb.cavity(0.15)
    col = nb.mix(nb.math("MULTIPLY", nb.math("SUBTRACT", 1.0, cav), 0.35), col, srgb("#2a2018"))
    nb.set("Base Color", col)
    nb.set("Roughness", nb.mix(0.5, nb.bw(rgh.outputs["Color"]), rough, data="FLOAT"))
    nb.set("Sheen Weight", 0.5)
    h = nb.bw(dif.outputs["Color"])
    if seam is not None:
        h = nb.math("SUBTRACT", h, nb.math("MULTIPLY", seam, 0.6))
    nb.set("Normal", nb.bump(h, 0.35, 0.01))
    return mat


def wicker(name="wicker", stake=0.14, weaver=0.055, tint="#c39a5f", stake_hex="#9c7444", uv_scale=1.0):
    """Woven basket wall on src UV in metres (u along the wall, v up).

    Horizontal weavers (`weaver` m high, rounded) pass alternately over and under
    vertical stakes every `stake` m (checkerboard on stake/weaver indices); where a
    weaver dips under, the stake shows through. Gaps between rows go dark.
    """
    mat, nb = _new(name, ("hessian_380",))
    if nb is None:
        return mat
    uv = nb.add("ShaderNodeUVMap", uv_map="src").outputs["UV"]
    sep = nb.add("ShaderNodeSeparateXYZ")
    nb.link(uv, sep.inputs[0])
    u = nb.math("MULTIPLY", sep.outputs["X"], uv_scale)
    v = nb.math("MULTIPLY", sep.outputs["Y"], uv_scale)
    si = nb.math("FLOOR", nb.math("DIVIDE", u, stake))
    bi = nb.math("FLOOR", nb.math("DIVIDE", v, weaver))
    over = nb.math("MODULO", nb.math("ADD", si, bi), 2.0)
    fu = nb.math("FRACT", nb.math("DIVIDE", u, stake))
    fv = nb.math("FRACT", nb.math("DIVIDE", v, weaver))
    hv = nb.math("POWER", nb.math("SINE", nb.math("MULTIPLY", fv, math.pi)), 0.5)
    su = nb.math("SINE", nb.math("MULTIPLY", fu, math.pi))
    du = nb.math("DIVIDE", nb.math("ABSOLUTE", nb.math("SUBTRACT", fu, 0.5)), 0.17)
    stake_prof = nb.math("SQRT", nb.math("SUBTRACT", 1.0, nb.math("MINIMUM", nb.math("MULTIPLY", du, du), 1.0)))
    stake_mask = nb.math("MULTIPLY", nb.math("SUBTRACT", 1.0, over), nb.math("LESS_THAN", du, 1.0))
    weav_h = nb.math("MULTIPLY", hv, nb.math("ADD", 0.62, nb.math("MULTIPLY", nb.mix(over, nb.math("SUBTRACT", 1.0, su), su, data="FLOAT"), 0.38)))
    h = nb.mix(stake_mask, weav_h, nb.math("MULTIPLY", stake_prof, 0.95), data="FLOAT")
    wn = nb.add("ShaderNodeTexWhiteNoise", noise_dimensions="2D")
    comb = nb.add("ShaderNodeCombineXYZ")
    nb.link(si, comb.inputs[0])
    nb.link(bi, comb.inputs[1])
    nb.link(comb.outputs[0], wn.inputs["Vector"])
    strand = nb.math("ADD", 0.8, nb.math("MULTIPLY", wn.outputs["Value"], 0.35))
    vec = nb.coords("UV", 6.0)
    dif = nb.image(_ph("hessian_380", "Diffuse"), vec)
    col = nb.mix(stake_mask, nb.mix(1.0, srgb(tint), strand, blend="MULTIPLY"), srgb(stake_hex))
    col = nb.mix(0.3, col, dif.outputs["Color"], blend="OVERLAY")
    col = nb.mix(1.0, col, nb.math("ADD", 0.18, nb.math("MULTIPLY", nb.math("POWER", h, 0.7), 0.95)), blend="MULTIPLY")
    nb.set("Base Color", col)
    nb.set("Roughness", nb.math("SUBTRACT", 0.78, nb.math("MULTIPLY", h, 0.15)))
    nb.set("Normal", nb.bump(h, 1.0, 0.02))
    return mat
