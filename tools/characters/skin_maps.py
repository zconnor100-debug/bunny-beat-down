# Bunny Beat Down — texture-space maps of a normalized character GLB.
#
# Library used by make_skins.py (runs inside Blender's Python: numpy for the
# maths, bpy only to decode/encode JPEG/PNG). For every material's base-colour
# texture it rasterizes the material's triangles into texture space and keeps,
# per texel:
#   tri    triangle index (-1 = not covered by any triangle)
#   bary   barycentric weights inside that triangle
# and per triangle: UV island id, dominant joint name, rest-pose positions,
# normals and (if present) vertex colours, so a skin recipe can select regions
# by bone, by 3D position (glTF space: x = character's left, y = up,
# z = forward, metres) or by colour. Uncovered texels near an island (the
# texture's bleed padding) inherit the nearest island's data, so recolours do
# not leave old-colour halos at UV seams once the GPU mip-maps the texture.
import os
import sys
import tempfile

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.dont_write_bytecode = True
import gltf_bind  # noqa: E402


# ----------------------------------------------------------------------------- images
def decode_image(data, mime):
    """bytes -> float32 (H, W, 4) sRGB-encoded RGBA, row 0 = top (glTF v = 0)."""
    import bpy
    suffix = ".jpg" if "jpeg" in (mime or "") else ".png"
    fd, path = tempfile.mkstemp(prefix="bbd-skin-", suffix=suffix)
    with os.fdopen(fd, "wb") as f:
        f.write(data)
    img = bpy.data.images.load(path)
    w, h = img.size
    px = np.empty(w * h * 4, dtype=np.float32)
    img.pixels.foreach_get(px)
    bpy.data.images.remove(img)
    os.unlink(path)
    return px.reshape(h, w, 4)[::-1].copy()


def encode_jpeg(rgb, path, quality=90):
    """float (H, W, 3) sRGB in 0..1, row 0 = top -> JPEG file."""
    import bpy
    h, w = rgb.shape[:2]
    img = bpy.data.images.new("bbd_skin_out", w, h, alpha=False)
    px = np.ones((h, w, 4), dtype=np.float32)
    px[..., :3] = np.clip(rgb[::-1], 0.0, 1.0)
    img.pixels.foreach_set(px.ravel())
    img.filepath_raw = path
    img.file_format = "JPEG"
    img.save(filepath=path, quality=quality)
    bpy.data.images.remove(img)


# ----------------------------------------------------------------------------- mesh data
class Island:
    pass


def load(glb_path):
    """Returns {"materials": [ {name, image, size, texels, tris...} ], "joints": [...]}."""
    js, binc = gltf_bind.read_glb(glb_path)
    nodes = js["nodes"]
    skin = js["skins"][0]
    joint_names = [nodes[j]["name"] for j in skin["joints"]]
    images = {}
    out = []
    for mesh in js["meshes"]:
        for prim in mesh["primitives"]:
            mat = js["materials"][prim["material"]]
            bct = mat.get("pbrMetallicRoughness", {}).get("baseColorTexture")
            if bct is None:
                continue
            src = js["textures"][bct["index"]]["source"]
            uv_set = "TEXCOORD_%d" % bct.get("texCoord", 0)
            at = prim["attributes"]
            P = gltf_bind.accessor(js, binc, at["POSITION"])
            N = gltf_bind.accessor(js, binc, at["NORMAL"]) if "NORMAL" in at else np.zeros_like(P)
            UV = gltf_bind.accessor(js, binc, at[uv_set])
            J = gltf_bind.accessor(js, binc, at["JOINTS_0"]).astype(int)
            Wt = gltf_bind.accessor(js, binc, at["WEIGHTS_0"])
            C = gltf_bind.accessor(js, binc, at["COLOR_0"])[:, :3] if "COLOR_0" in at else None
            I = gltf_bind.accessor(js, binc, prim["indices"]).astype(int).reshape(-1, 3)
            if src not in images:
                im = js["images"][src]
                bv = js["bufferViews"][im["bufferView"]]
                o = bv.get("byteOffset", 0)
                images[src] = decode_image(binc[o:o + bv["byteLength"]], im.get("mimeType"))
            out.append({"material": mat["name"], "image": src, "P": P, "N": N, "UV": UV, "J": J, "W": Wt,
                        "C": C, "I": I})
    return {"prims": out, "images": images, "joints": joint_names, "json": js}


def islands(prim):
    """UV islands: triangles connected through vertices that share UV + position."""
    UV, P, I = prim["UV"], prim["P"], prim["I"]
    key = np.round(np.concatenate([UV * 4096.0, P * 1e4], axis=1)).astype(np.int64)
    _, vid = np.unique(key, axis=0, return_inverse=True)
    vid = vid.ravel()
    parent = np.arange(vid.max() + 1)

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a

    for t in I:
        a, b, c = find(vid[t[0]]), find(vid[t[1]]), find(vid[t[2]])
        parent[b] = a
        parent[find(c)] = a
    roots = np.array([find(vid[t[0]]) for t in I])
    _, isl = np.unique(roots, return_inverse=True)
    return isl.ravel()


def rasterize(prims, shape, pad=10):
    """Texel maps for a list of primitives sharing one texture of `shape` (H, W).
    Returns dict: tri (H, W) global triangle index or -1, bary (H, W, 3),
    plus concatenated per-triangle arrays and per-texel interpolated maps."""
    H, Wd = shape
    tri_map = -np.ones((H, Wd), dtype=np.int64)
    bary = np.zeros((H, Wd, 3), dtype=np.float32)
    tris, tri_prim, tri_isl, isl_base = [], [], [], 0
    for k, prim in enumerate(prims):
        isl = islands(prim) + isl_base
        isl_base = isl.max() + 1
        tri_isl.append(isl)
        tri_prim.append(np.full(len(prim["I"]), k))
        tris.append(prim["I"])
    offsets = np.cumsum([0] + [len(p["I"]) for p in prims])
    for k, prim in enumerate(prims):
        uvp = prim["UV"] * np.array([Wd, H]) - 0.5            # texel-centre coordinates
        for ti, t in enumerate(prim["I"]):
            a, b, c = uvp[t[0]], uvp[t[1]], uvp[t[2]]
            x0 = max(int(np.floor(min(a[0], b[0], c[0]))), 0)
            x1 = min(int(np.ceil(max(a[0], b[0], c[0]))), Wd - 1)
            y0 = max(int(np.floor(min(a[1], b[1], c[1]))), 0)
            y1 = min(int(np.ceil(max(a[1], b[1], c[1]))), H - 1)
            if x1 < x0 or y1 < y0:
                continue
            xs, ys = np.meshgrid(np.arange(x0, x1 + 1), np.arange(y0, y1 + 1))
            den = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
            if abs(den) < 1e-12:
                continue
            l0 = ((b[1] - c[1]) * (xs - c[0]) + (c[0] - b[0]) * (ys - c[1])) / den
            l1 = ((c[1] - a[1]) * (xs - c[0]) + (a[0] - c[0]) * (ys - c[1])) / den
            l2 = 1.0 - l0 - l1
            inside = (l0 >= -0.02) & (l1 >= -0.02) & (l2 >= -0.02)
            if not inside.any():
                continue
            yy, xx = ys[inside], xs[inside]
            tri_map[yy, xx] = offsets[k] + ti
            bary[yy, xx] = np.stack([l0[inside], l1[inside], l2[inside]], axis=1)
    covered = tri_map >= 0
    # bleed padding: grow the triangle map outwards (nearest covered texel wins)
    grown = tri_map.copy()
    gbary = bary.copy()
    for _ in range(pad):
        empty = grown < 0
        if not empty.any():
            break
        for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
            src = np.roll(grown, (dy, dx), axis=(0, 1))
            srcb = np.roll(gbary, (dy, dx), axis=(0, 1))
            take = empty & (src >= 0)
            grown[take] = src[take]
            gbary[take] = srcb[take]
            empty = grown < 0
    return {"tri": grown, "bary": gbary, "covered": covered, "offsets": offsets,
            "tri_prim": np.concatenate(tri_prim), "tri_isl": np.concatenate(tri_isl)}


def texel_attributes(prims, rast, joint_names):
    """Per-texel interpolated rest position, normal, vertex colour, and the
    dominant joint name / island id of the texel's triangle."""
    tri, bary = rast["tri"], rast["bary"]
    H, Wd = tri.shape
    valid = tri >= 0
    allP, allN, allC, allTri, dom = [], [], [], [], []
    vbase = 0
    for prim in prims:
        allP.append(prim["P"])
        allN.append(prim["N"])
        allC.append(prim["C"] if prim["C"] is not None else np.ones_like(prim["P"]))
        allTri.append(prim["I"] + vbase)
        # dominant joint per triangle: largest summed weight over its 3 vertices
        J, W = prim["J"], prim["W"]
        acc = np.zeros((len(prim["I"]), len(joint_names)))
        for corner in range(3):
            v = prim["I"][:, corner]
            for s in range(J.shape[1]):
                np.add.at(acc, (np.arange(len(v)), J[v, s]), W[v, s])
        dom.append(np.argmax(acc, axis=1))
        vbase += len(prim["P"])
    P, N, C = np.concatenate(allP), np.concatenate(allN), np.concatenate(allC)
    T = np.concatenate(allTri)
    dom = np.concatenate(dom)
    t = np.where(valid, tri, 0)
    vi = T[t]                                                    # (H, W, 3)
    pos = (P[vi] * bary[..., None]).sum(axis=2)
    nrm = (N[vi] * bary[..., None]).sum(axis=2)
    vcol = (C[vi] * bary[..., None]).sum(axis=2)
    nrm /= np.maximum(np.linalg.norm(nrm, axis=2, keepdims=True), 1e-9)
    bone = np.where(valid, dom[t], -1)
    isl = np.where(valid, rast["tri_isl"][t], -1)
    mat = np.where(valid, rast["tri_prim"][t], -1)
    return {"valid": valid, "pos": pos, "normal": nrm, "vcol": vcol, "bone": bone, "island": isl, "prim": mat}


# ----------------------------------------------------------------------------- colour
def srgb_to_linear(c):
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def linear_to_srgb(c):
    c = np.clip(c, 0.0, 1.0)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(c, 1 / 2.4) - 0.055)


_M1 = np.array([[0.4122214708, 0.5363325363, 0.0514459929],
                [0.2119034982, 0.6806995451, 0.1073969566],
                [0.0883024619, 0.2817188376, 0.6299787005]])
_M2 = np.array([[0.2104542553, 0.7936177850, -0.0040720468],
                [1.9779984951, -2.4285922050, 0.4505937099],
                [0.0259040371, 0.7827717662, -0.8086757660]])


def srgb_to_oklab(rgb):
    lms = srgb_to_linear(rgb) @ _M1.T
    return np.cbrt(lms) @ _M2.T


def oklab_to_srgb(lab):
    lms = (lab @ np.linalg.inv(_M2).T) ** 3
    return linear_to_srgb(lms @ np.linalg.inv(_M1).T)


def lch(lab):
    L, a, b = lab[..., 0], lab[..., 1], lab[..., 2]
    return L, np.hypot(a, b), (np.degrees(np.arctan2(b, a)) + 360.0) % 360.0


def dilate_fill(img, known, target, iters=12):
    """Copy values from `known` texels into nearby `target` texels that are not
    known (the bleed padding around UV islands), nearest-first."""
    out = img.copy()
    have = known.copy()
    need = target & ~known
    for _ in range(iters):
        if not need.any():
            break
        for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
            src_have = np.roll(have, (dy, dx), axis=(0, 1))
            take = need & src_have
            if take.any():
                out[take] = np.roll(out, (dy, dx), axis=(0, 1))[take]
                have = have | take
                need = need & ~take
    return out
